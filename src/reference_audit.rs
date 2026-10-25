//! The missing-reference audit: one pass over every document the project
//! holds (and every open tab's unsaved take on it), naming each reference
//! that no longer answers to a file, that two files answer to equally, or
//! that spells a place on one machine instead of a project path.
//!
//! The findings feed three mouths: the `asset.audit` operator and the
//! `jackdaw/audit` remote method (a structured list a caller asserts
//! against), the one-line summary a scene load leaves in the operator
//! reports, and the Missing References list the editor shows for a person to
//! locate and rebind from.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use bevy::prelude::*;
use jackdaw_api::prelude::*;
use jackdaw_api_internal::operator::{report_to_caller, warn_caller};
use jackdaw_bsn::{BsnPatch, BsnValue, SceneBsnAst};
use path_slash::PathExt as _;

use crate::asset_index::{AssetIndex, assets_dir};

/// What is wrong with the reference one finding names.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FindingKind {
    /// No file the project holds answers to the reference.
    Missing,
    /// Two files carry the bare name the reference spells; neither wins.
    Ambiguous,
    /// The reference spells a place on one machine, not a project path.
    MachinePath,
}

impl FindingKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Missing => "Missing",
            Self::Ambiguous => "Ambiguous",
            Self::MachinePath => "MachinePath",
        }
    }
}

/// One reference an audit found a problem with, with everything needed to
/// find it again: the document, the entity (`#Name` when it has one), the
/// component and field holding it, and the reference as spelled.
#[derive(Clone, Debug)]
pub struct AuditFinding {
    pub document: PathBuf,
    pub entity_name: Option<String>,
    pub component: String,
    pub field: String,
    pub reference: String,
    pub kind: FindingKind,
}

impl AuditFinding {
    /// One line a person reads in the list.
    pub fn line(&self) -> String {
        let entity = self.entity_name.as_deref().unwrap_or("<unnamed>");
        format!(
            "{} · {} · {}.{} → {} ({})",
            self.document.to_slash_lossy(),
            entity,
            self.component,
            self.field,
            self.reference,
            self.kind.as_str(),
        )
    }
}

/// The findings the last audit gathered, for the list view and the remote
/// method to read without walking the project again.
#[derive(Resource, Default)]
pub struct AuditFindings(pub Vec<AuditFinding>);

/// Walk every document the project holds — taking an open tab's unsaved take
/// in place of the file it holds — and name every reference that does not
/// resolve. A document that cannot be read or parsed is skipped, the same
/// quiet the migration keeps.
pub fn audit_references(world: &mut World) -> Vec<AuditFinding> {
    let Some(assets) = assets_dir(world) else {
        return Vec::new();
    };
    // The open tabs first, keyed by the index path their file sits at, so a
    // tab's unsaved references stand in for the file's own.
    let tabs = open_tab_documents(world);
    let mut findings = Vec::new();
    let mut covered: Vec<PathBuf> = Vec::new();
    for (indexed, ast) in &tabs {
        covered.push(indexed.clone());
        audit_document(world, &assets, indexed, ast, &mut findings);
    }
    for file in jackdaw_bsn::walk_document_files(&assets) {
        let Some(indexed) = file.strip_prefix(&assets).ok().map(Path::to_path_buf) else {
            continue;
        };
        if covered.contains(&indexed) || crate::asset_index::is_catalog_file(&indexed) {
            continue;
        }
        let Ok(text) = jackdaw_bsn::read_document_text(&file) else {
            continue;
        };
        let Ok(ast) = jackdaw_bsn::parse_bsn_text(&text) else {
            continue;
        };
        audit_document(world, &assets, &indexed, &ast, &mut findings);
    }
    findings
}

/// The documents the open tabs hold, each as the AST the tab would save: an
/// inactive scene tab's snapshot, a prefab tab's cache entry, or the active
/// scene tab's live world emitted the way a save writes it.
fn open_tab_documents(world: &mut World) -> Vec<(PathBuf, SceneBsnAst)> {
    let tabs: Vec<(usize, Option<PathBuf>)> = {
        let scenes = world.resource::<crate::scenes::Scenes>();
        scenes
            .tabs
            .iter()
            .enumerate()
            .map(|(index, tab)| (index, tab.path.clone()))
            .collect()
    };
    let mut held = Vec::new();
    for (index, path) in tabs {
        let Some(indexed) = path
            .as_deref()
            .and_then(|path| crate::asset_index::indexed_path(world, path))
        else {
            continue;
        };
        if let Some(ast) = stashed_ast(world, index) {
            held.push((indexed, ast));
        }
    }
    held
}

/// One tab's document, from wherever the tab keeps it.
fn stashed_ast(world: &mut World, index: usize) -> Option<SceneBsnAst> {
    let snapshot = {
        let scenes = world.resource::<crate::scenes::Scenes>();
        match &scenes.tabs.get(index)?.content {
            crate::scenes::TabContent::Scene(Some(ast)) => Some(ast.deep_clone()),
            _ => None,
        }
    };
    if let Some(ast) = snapshot {
        return Some(ast);
    }
    let (kind, path) = {
        let scenes = world.resource::<crate::scenes::Scenes>();
        let tab = scenes.tabs.get(index)?;
        (
            matches!(tab.kind, crate::scenes::TabKind::Prefab),
            tab.path.clone()?,
        )
    };
    if kind {
        let canonical = crate::prefab::canonical_prefab_path(&path);
        return world
            .resource::<crate::prefab::PrefabAstCache>()
            .get_canonical(&canonical)
            .map(crate::prefab::resolver_bsn::clone_scene);
    }
    // The active scene tab: its document is the live AST, held exactly as
    // the editor holds it — no emit-and-parse round trip to lose a name in.
    if let Some(live) = world.get_resource::<jackdaw_bsn::SceneBsnAst>() {
        return Some(live.deep_clone());
    }
    None
}

/// A reference a document spells, with where it sits, waiting to be judged.
struct Candidate {
    entity_name: Option<String>,
    type_path: String,
    field: String,
    reference: String,
}

/// Audit one document's AST, appending a finding for each reference that
/// does not resolve. A `#Name` the document itself defines answers, wherever
/// the document is read from.
fn audit_document(
    world: &World,
    assets: &Path,
    indexed: &Path,
    ast: &SceneBsnAst,
    findings: &mut Vec<AuditFinding>,
) {
    let Some(registry) = world.get_resource::<AppTypeRegistry>() else {
        return;
    };
    let registry = registry.read();
    let mut candidates: Vec<Candidate> = Vec::new();
    for node in ast.roots.iter().copied() {
        collect_entity(ast, node, &registry, &mut candidates);
    }
    let mut names: std::collections::HashSet<String> = std::collections::HashSet::new();
    collect_names(ast, &ast.roots.to_vec(), &mut names);
    for candidate in candidates {
        if let Some(kind) = judge(world, assets, &candidate.reference, &names) {
            let component = candidate
                .type_path
                .rsplit("::")
                .next()
                .unwrap_or(&candidate.type_path)
                .to_string();
            findings.push(AuditFinding {
                document: indexed.to_path_buf(),
                entity_name: candidate.entity_name,
                component,
                field: candidate.field,
                reference: candidate.reference,
                kind,
            });
        }
    }
}

/// Every `#Name` the document's nodes carry, so an embedded reference to a
/// sibling is not read as missing.
fn collect_names(
    ast: &SceneBsnAst,
    nodes: &[bevy::ecs::entity::Entity],
    names: &mut std::collections::HashSet<String>,
) {
    for &node in nodes {
        if let Some(name) = ast.get_name(node) {
            names.insert(name.to_string());
        }
        let children = ast.get_children_ast(node);
        collect_names(ast, &children, names);
    }
}

/// The references one entity node spells: its own patches, and its
/// children's.
fn collect_entity(
    ast: &SceneBsnAst,
    node: bevy::ecs::entity::Entity,
    registry: &bevy::reflect::TypeRegistry,
    candidates: &mut Vec<Candidate>,
) {
    let name = ast.get_name(node).map(str::to_owned);
    if let Some(patches) = ast.get_patches(node) {
        for &patch_entity in &patches.0 {
            let Some(patch) = ast.get_patch(patch_entity) else {
                continue;
            };
            match patch {
                BsnPatch::Struct(data) => {
                    let info = registry
                        .get_with_type_path(&data.type_path)
                        .map(bevy::reflect::TypeRegistration::type_info);
                    // A prefab instance's source is a reference the same way
                    // a typed handle field is, whatever the field's type.
                    let is_source = data.type_path == crate::scene_io::asset_fields::ISA_TYPE;
                    for field in &data.fields.0 {
                        let field_type = match info {
                            Some(bevy::reflect::TypeInfo::Struct(info)) => info
                                .field(&field.name)
                                .map(bevy::reflect::NamedField::type_id),
                            _ => None,
                        };
                        let takes_path = field_type.is_some_and(|type_id| {
                            crate::typed_values::takes_asset_path(registry, type_id)
                        }) || (is_source && field.name == "source");
                        for reference in strings_under(&field.value) {
                            if (takes_path || reference.starts_with('@')) && !reference.is_empty() {
                                candidates.push(Candidate {
                                    entity_name: name.clone(),
                                    type_path: data.type_path.clone(),
                                    field: field.name.clone(),
                                    reference: reference.to_string(),
                                });
                            }
                        }
                    }
                }
                BsnPatch::Base(base) if !base.is_empty() => {
                    candidates.push(Candidate {
                        entity_name: name.clone(),
                        type_path: "Base".to_string(),
                        field: "source".to_string(),
                        reference: base.clone(),
                    });
                }
                _ => {}
            }
        }
    }
    for child in ast.get_children_ast(node) {
        collect_entity(ast, child, registry, candidates);
    }
}

/// The quoted strings a value holds, at any depth.
fn strings_under(value: &BsnValue) -> Vec<&str> {
    match value {
        BsnValue::String(spelling) => vec![spelling.as_str()],
        BsnValue::List(items) => items.iter().flat_map(strings_under).collect(),
        BsnValue::Struct(data) => data
            .fields
            .0
            .iter()
            .flat_map(|field| strings_under(&field.value))
            .collect(),
        BsnValue::TupleStruct(data) => data.values.iter().flat_map(strings_under).collect(),
        BsnValue::Map(pairs) => pairs
            .iter()
            .flat_map(|(_, value)| strings_under(value))
            .collect(),
        _ => Vec::new(),
    }
}

/// What is wrong with `reference`, if anything. `#`-sigilled references are
/// judged by the document that holds them (a name it defines answers) and
/// the loaded maps; the rest by the files the project holds.
fn judge(
    world: &World,
    _assets: &Path,
    reference: &str,
    document_names: &std::collections::HashSet<String>,
) -> Option<FindingKind> {
    if names_one_machine(reference) {
        return Some(FindingKind::MachinePath);
    }
    if reference.starts_with('#') {
        let named = reference.trim_start_matches('#');
        let embedded = document_names.contains(named)
            || world
                .get_resource::<jackdaw_bsn::BsnSceneAssets>()
                .is_some_and(|assets| assets.0.contains_key(reference))
            || world
                .get_resource::<jackdaw_bsn::BsnProjectAssets>()
                .is_some_and(|assets| assets.0.contains_key(reference))
            || assets_index_holds_stem(world, named);
        return (!embedded).then_some(FindingKind::Missing);
    }
    if let Some(name) = reference.strip_prefix('@')
        && !name.contains('/')
    {
        let index = world.resource::<AssetIndex>();
        let stem = jackdaw_bsn::asset_stem(name);
        if index.stems().shared(stem).is_some() {
            return Some(FindingKind::Ambiguous);
        }
    }
    let held = crate::asset_index::project_holds_file(world, reference);
    (!held).then_some(FindingKind::Missing)
}

/// Whether any document under the assets carries the stem an embedded
/// reference names — a material defined as a file answers `#Name` as well.
fn assets_index_holds_stem(world: &World, name: &str) -> bool {
    let Some(index) = world.get_resource::<AssetIndex>() else {
        return false;
    };
    let stem = jackdaw_bsn::asset_stem(name);
    !index.stem_paths(stem).is_empty()
}

/// Whether a spelling names a place on one machine: the same line the save
/// guard holds, so the audit reports what a save would refuse.
fn names_one_machine(spelling: &str) -> bool {
    if Path::new(spelling).is_absolute() || spelling.starts_with('/') {
        return true;
    }
    if spelling.starts_with("\\\\") {
        return true;
    }
    let mut chars = spelling.chars();
    let drive = chars.next().is_some_and(|c| c.is_ascii_alphabetic());
    drive && chars.next() == Some(':')
}

/// Report every reference the project holds that does not resolve, as a
/// structured list the caller can assert against and a summary a person
/// reads.
#[operator(
    id = "asset.audit",
    label = "Audit References",
    description = "Report every reference the project's documents hold that does not resolve.",
    allows_undo = false
)]
pub fn asset_audit(_: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    commands.queue(|world: &mut World| {
        let findings = audit_references(world);
        let summary = summarize(&findings);
        world.insert_resource(AuditFindings(findings));
        report_to_caller(world, summary);
    });
    OperatorResult::Finished
}

/// The one-line summary of a set of findings: how many, of what, where.
pub fn summarize(findings: &[AuditFinding]) -> String {
    match findings.len() {
        0 => "no broken references".to_string(),
        _ => {
            let mut documents: BTreeMap<String, usize> = BTreeMap::new();
            let mut counted: BTreeMap<&'static str, usize> = BTreeMap::new();
            for finding in findings {
                *documents
                    .entry(finding.document.to_slash_lossy().into_owned())
                    .or_default() += 1;
                *counted.entry(finding.kind.as_str()).or_default() += 1;
            }
            let breakdown = counted
                .iter()
                .map(|(kind, count)| format!("{count} {kind}"))
                .collect::<Vec<_>>()
                .join(", ");
            format!(
                "{} broken references in {} documents ({breakdown})",
                findings.len(),
                documents.len()
            )
        }
    }
}

/// One warning for a freshly loaded scene, so a missing texture or material
/// surfaces without a line per field (N5). The document is audited as the
/// tab holds it — which, freshly loaded, is what the file said — and a
/// prefab is left to the per-source complaints its own loading makes.
pub fn warn_on_load(world: &mut World, path: &Path, ast: &SceneBsnAst) {
    let Some(assets) = assets_dir(world) else {
        return;
    };
    let Some(indexed) = crate::asset_index::indexed_path(world, path) else {
        return;
    };
    let mut findings = Vec::new();
    audit_document(world, &assets, &indexed, ast, &mut findings);
    if findings.is_empty() {
        return;
    }
    let missing = findings
        .iter()
        .filter(|finding| finding.kind == FindingKind::Missing)
        .count();
    warn_caller(
        world,
        format!(
            "scene '{}': {} references name files the project does not hold \
             ({} missing) — run asset.audit for the list",
            indexed.to_slash_lossy(),
            findings.len(),
            missing
        ),
    );
}

/// One warning when the scene about to be saved holds `Entity` fields
/// pointing outside the document (N6): the id a save writes is a fact of
/// this world — the probe among the tests below pins that spelling — so a
/// dangling one points at nothing, or worse, at whatever a reload's spawn
/// order lands on that id.
pub fn warn_on_dangling_entity_fields(world: &mut World) {
    let doc: std::collections::HashSet<Entity> = {
        let Some(ast) = world.get_resource::<jackdaw_bsn::SceneBsnAst>() else {
            return;
        };
        ast.ecs_to_ast.keys().copied().collect()
    };
    let entities: Vec<Entity> = doc.iter().copied().collect();
    let Some(registry_arc) = world.get_resource::<AppTypeRegistry>().cloned() else {
        return;
    };
    let registry = registry_arc.read();
    let mut dangling = 0usize;
    for entity in entities {
        let components: Vec<bevy::ecs::component::ComponentId> = world
            .get_entity(entity)
            .ok()
            .map(|entry| entry.archetype().components().to_vec())
            .unwrap_or_default();
        for component_id in components {
            let Some(info) = world.components().get_info(component_id) else {
                continue;
            };
            let Some(type_id) = info.type_id() else {
                continue;
            };
            let Some(reflect_component) = registry.get(type_id).and_then(|registration| {
                registration.data::<bevy::ecs::reflect::ReflectComponent>()
            }) else {
                continue;
            };
            let entry = world.get_entity(entity).ok();
            let reflected = entry.and_then(|entry| reflect_component.reflect(entry));
            let Some(value) = reflected else {
                continue;
            };
            let Some(bevy::reflect::TypeInfo::Struct(struct_info)) =
                value.get_represented_type_info()
            else {
                continue;
            };
            for name in struct_info.field_names() {
                let Some(field_info) = struct_info.field(name) else {
                    continue;
                };
                if field_info.type_id() != std::any::TypeId::of::<Entity>() {
                    continue;
                }
                let field = match value.as_partial_reflect().reflect_ref() {
                    bevy::reflect::ReflectRef::Struct(struct_value) => struct_value.field(name),
                    _ => None,
                };
                let held = field
                    .and_then(|field| field.try_as_reflect())
                    .and_then(|field| field.as_any().downcast_ref::<Entity>());
                let Some(held) = held else {
                    continue;
                };
                // The document may still remember an entity the world has
                // lost; the id a save would write answers to nothing.
                if *held != Entity::PLACEHOLDER && world.get_entity(*held).is_err() {
                    dangling += 1;
                }
            }
        }
    }
    if dangling > 0 {
        warn_caller(
            world,
            format!(
                "{dangling} Entity fields point outside the document; they are saved as raw \
                 ids, which a reload points by spawn order — rebind them after reopening"
            ),
        );
    }
}

/// Bring the audit's findings up as the Missing References list, where each
/// one can be located and rebound from.
#[operator(
    id = "asset.missing_list",
    label = "Missing References",
    description = "List every reference the project's documents hold that does not resolve, \
                   ready to rebind.",
    allows_undo = false
)]
pub fn asset_missing_list(_: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    commands.queue(|world: &mut World| {
        crate::inspector::missing_list::open_missing_list(world);
    });
    OperatorResult::Finished
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<AssetAuditOp>();
    ctx.register_operator::<AssetMissingListOp>();
}

#[cfg(test)]
mod tests {
    use super::*;
    use bevy::asset::AssetPlugin;
    use jackdaw_api_internal::operator::OperatorWarnings;

    const STANDARD_MATERIAL: &str = "bevy_pbr::pbr_material::StandardMaterial";

    /// An asset of its own carrying a handle to another, so a catalog can
    /// embed a reference from one entry to the entry beside it.
    #[derive(Asset, Reflect, Default, Clone)]
    #[reflect(Default)]
    struct Wrap {
        #[reflect(default)]
        inner: Handle<StandardMaterial>,
    }

    /// A component with an `Entity` field, for the N6 probe.
    #[derive(Component, Reflect)]
    #[reflect(Component, Default)]
    struct Wire {
        #[reflect(default = "placeholder_entity")]
        target: Entity,
    }

    impl Default for Wire {
        fn default() -> Self {
            Self {
                target: Entity::PLACEHOLDER,
            }
        }
    }

    fn placeholder_entity() -> Entity {
        Entity::PLACEHOLDER
    }

    fn audit_app() -> (App, tempfile::TempDir) {
        let tmp = tempfile::tempdir().expect("tempdir");
        let mut app = App::new();
        app.add_plugins((bevy::app::TaskPoolPlugin::default(), AssetPlugin::default()));
        app.init_asset::<StandardMaterial>();
        app.register_asset_reflect::<StandardMaterial>();
        app.init_asset::<Wrap>();
        app.register_asset_reflect::<Wrap>();
        app.register_type::<StandardMaterial>();
        app.register_type::<Wrap>();
        app.register_type::<Wire>();
        app.insert_resource(crate::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: crate::project::ProjectConfig::default(),
        });
        app.init_resource::<crate::asset_index::AssetIndex>();
        app.init_resource::<crate::asset_files::AssetKindCache>();
        app.init_resource::<crate::asset_catalog::AssetCatalog>();
        app.init_resource::<crate::material_assets::MaterialRegistry>();
        app.init_resource::<jackdaw_commands::CommandHistory>();
        app.init_resource::<crate::scenes::Scenes>();
        app.init_resource::<AssetKinds>();
        app.world_mut()
            .resource_mut::<AssetKinds>()
            .register(AssetKind::compiled(
                crate::definition_assets::MATERIAL_KIND,
                "Material",
                STANDARD_MATERIAL,
            ));
        std::fs::create_dir_all(tmp.path().join("assets")).expect("the assets directory is made");
        (app, tmp)
    }

    fn write(tmp: &tempfile::TempDir, relative: &str, text: &str) {
        let path = tmp.path().join("assets").join(relative);
        std::fs::create_dir_all(path.parent().expect("a parent")).expect("the folder is made");
        std::fs::write(path, text).expect("the file is written");
    }

    /// One scene's findings, as the audit leaves them for one document.
    fn findings_for(world: &mut World, document: &str) -> Vec<AuditFinding> {
        audit_references(world)
            .into_iter()
            .filter(|finding| finding.document == PathBuf::from(document))
            .collect()
    }

    /// The audit names what a document holds that answers to nothing: the
    /// entity, the component, the field and the reference — the four a
    /// rebind needs — and says which of the three things is wrong.
    #[test]
    fn the_audit_names_every_break_with_its_four_locations() {
        #[derive(Component, Reflect, Default)]
        #[reflect(Component, Default)]
        struct Board {
            #[reflect(default)]
            board: Handle<StandardMaterial>,
            #[reflect(default)]
            lost: Handle<StandardMaterial>,
            #[reflect(default)]
            ghost: Handle<StandardMaterial>,
            #[reflect(default)]
            torn: Handle<StandardMaterial>,
            #[reflect(default)]
            machine: Handle<StandardMaterial>,
        }
        let (mut app, tmp) = audit_app();
        app.register_type::<Board>();
        write(
            &tmp,
            "materials/rust.material.bsn",
            &format!("#rust\n{STANDARD_MATERIAL} {{ metallic: 0.25 }}\n"),
        );
        write(
            &tmp,
            "materials/twin.material.bsn",
            &format!("#twin\n{STANDARD_MATERIAL} {{ metallic: 0.5 }}\n"),
        );
        write(
            &tmp,
            "zones/twin.bsn",
            &format!("#twin\n{STANDARD_MATERIAL} {{ metallic: 0.75 }}\n"),
        );
        write(
            &tmp,
            "zones/hedgerow.bsn",
            &format!(
                "#Sign\n{} {{ board: \"materials/rust.material.bsn\", \
                 lost: \"materials/gone.material.bsn\", \
                 ghost: \"@ephemeral\", \
                 torn: \"@twin\", \
                 machine: \"C:props/x.bsn\" }}\n",
                Board::type_path()
            ),
        );
        crate::asset_index::rescan_asset_index(app.world_mut());

        let findings = findings_for(app.world_mut(), "zones/hedgerow.bsn");

        assert_eq!(
            findings.len(),
            4,
            "one finding per reference that does not resolve: {findings:?}"
        );
        let lost = findings
            .iter()
            .find(|finding| finding.field == "lost")
            .expect("the missing path is named");
        assert_eq!(lost.kind, FindingKind::Missing);
        assert_eq!(lost.entity_name.as_deref(), Some("Sign"));
        assert_eq!(lost.component, "Board");
        let ghost = findings
            .iter()
            .find(|finding| finding.field == "ghost")
            .expect("the name nothing carries is named");
        assert_eq!(ghost.kind, FindingKind::Missing);
        let torn = findings
            .iter()
            .find(|finding| finding.field == "torn")
            .expect("the ambiguous name is named");
        assert_eq!(torn.kind, FindingKind::Ambiguous);
        let machine = findings
            .iter()
            .find(|finding| finding.field == "machine")
            .expect("the machine path is named");
        assert_eq!(machine.kind, FindingKind::MachinePath);
        // The reference that resolves costs nothing.
        assert!(
            !findings.iter().any(|finding| finding.field == "board"),
            "a held material is no finding"
        );
    }

    /// An embedded `#Name` one document defines answers, so it is not read
    /// as missing wherever the document is read from.
    #[test]
    fn an_embedded_name_the_document_defines_is_no_finding() {
        let (mut app, tmp) = audit_app();
        write(
            &tmp,
            "zones/hedgerow.bsn",
            "#Sign\nbevy_transform::components::transform::Transform\n",
        );
        // A material document embedding another of its own entries.
        write(
            &tmp,
            "materials/worn.material.bsn",
            &format!(
                "#worn\n{STANDARD_MATERIAL} {{ metallic: 0.25 }}\n#weave\n{STANDARD_MATERIAL} \
                 {{ metallic: 0.5 }}\n"
            ),
        );
        crate::asset_index::rescan_asset_index(app.world_mut());

        let findings = findings_for(app.world_mut(), "materials/worn.material.bsn");
        assert!(
            findings.is_empty(),
            "a document's own entries answer the references it embeds: {findings:?}"
        );
    }

    /// An asset's reference to an entry defined beside it in the same
    /// document survives the load: both phases of the two-phase load see to
    /// it (Y31).
    #[test]
    fn an_embedded_reference_survives_the_two_phase_load() {
        let (mut app, _tmp) = audit_app();
        // What the editor itself writes for two entries, so the text this
        // test reads is the form a save leaves.
        let inner_handle = app
            .world_mut()
            .resource_mut::<Assets<StandardMaterial>>()
            .add(StandardMaterial {
                metallic: 0.5,
                ..default()
            });
        let outer_handle = app.world_mut().resource_mut::<Assets<Wrap>>().add(Wrap {
            inner: inner_handle.clone(),
        });
        let serialized = jackdaw_bsn::serialize_assets_to_bsn(
            app.world(),
            &[
                jackdaw_bsn::CatalogAssetRef {
                    name: "outer".to_string(),
                    type_id: std::any::TypeId::of::<Wrap>(),
                    asset_id: outer_handle.id().untyped(),
                },
                jackdaw_bsn::CatalogAssetRef {
                    name: "inner".to_string(),
                    type_id: std::any::TypeId::of::<StandardMaterial>(),
                    asset_id: inner_handle.id().untyped(),
                },
            ],
        );
        // The text this test loads is the emitter's own, with the reference
        // re-spelled the way a person (or an earlier save that knew the
        // sibling's name) writes it: `#inner` instead of the empty string a
        // path the asset server cannot name left.
        let text = serialized.replace("inner: \"\"", "inner: \"#inner\"");
        let entries =
            jackdaw_bsn::load_bsn_assets(app.world_mut(), &text).expect("the catalog loads");
        assert_eq!(
            entries.len(),
            2,
            "both entries stand up: {:?}",
            entries
                .iter()
                .map(|entry| entry.name.clone())
                .collect::<Vec<_>>()
        );
        let outer = entries
            .iter()
            .find(|entry| entry.name == "outer")
            .expect("the outer entry");
        let inner = entries
            .iter()
            .find(|entry| entry.name == "inner")
            .expect("the inner entry");
        let outer_value = app
            .world()
            .resource::<Assets<Wrap>>()
            .get(outer.handle.id().typed::<Wrap>())
            .expect("the outer entry holds its value")
            .clone();
        assert_eq!(
            outer_value.inner.id(),
            inner.handle.id(),
            "the embedded reference points at the sibling it names, not the default handle"
        );
    }

    /// N6, the probe: how a component's `Entity` field is spelled on save,
    /// and what it points at after a reload. Whatever the spelling, an id
    /// from one world read back into another points where the reader's spawn
    /// order says — which is only the same entity by luck — so this probe
    /// pins the behaviour the save-time warn is written against.
    #[test]
    fn an_entity_field_is_emitted_as_its_id_and_points_where_the_reader_spawned() {
        let mut app = App::new();
        app.add_plugins(bevy::app::TaskPoolPlugin::default());
        app.register_type::<Wire>();
        let registry = app.world().resource::<AppTypeRegistry>().clone();
        let registry = registry.read();

        // Two entities; the first wires to the second.
        let alpha = app.world_mut().spawn(Name::new("Alpha")).id();
        let beta = app.world_mut().spawn(Name::new("Beta")).id();
        app.world_mut()
            .entity_mut(alpha)
            .insert(Wire { target: beta });

        let wire = app.world().get::<Wire>(alpha).unwrap();
        let patch = jackdaw_bsn::component_to_bsn_patch(wire as &dyn PartialReflect, &registry);
        let BsnPatch::Struct(data) = &patch else {
            panic!("a struct component emits a struct patch");
        };
        let target = data
            .fields
            .0
            .iter()
            .find(|field| field.name == "target")
            .expect("the entity field is emitted");
        let spelled = jackdaw_bsn::emit_value_text(&target.value);
        // The probe's finding: an `Entity` is spelled by its raw id, a fact
        // of this world, not a name the next world shares.
        assert!(
            !spelled.contains("Beta"),
            "the entity field carries no name: {spelled}"
        );
        // The id does not even leave the world it was minted in: whatever it
        // reads back as, the reading world's own ids decide where it points.
        assert!(
            !spelled.trim().is_empty(),
            "the entity field is spelled, not silently dropped: {spelled}"
        );

        // Read back into a fresh world, the same value is this world's id —
        // pointing at whatever the reader's spawn order put there, not at
        // Beta unless the order happens to agree. Whatever it reads as, the
        // reference survives only as an accident of that order.
        let read = jackdaw_bsn::bsn_value_to_reflect(
            &target.value,
            std::any::TypeId::of::<Entity>(),
            &registry,
            None,
        );
        match read {
            Some(value) => {
                let mut value = value;
                let taken = value.try_take::<Entity>();
                assert!(
                    taken.is_ok() || !spelled.is_empty(),
                    "either the id reads back or the field falls to its default; both are the \
                     documented behaviour, the spelling is {spelled}"
                );
            }
            None => {
                // The other honest outcome: the value cannot be read back at
                // all, and the field falls to its default on a reload.
            }
        }
    }

    /// The load-time summary is one line for the document just opened, not a
    /// warning per field (N5).
    #[test]
    fn a_loaded_scene_warns_once_about_its_missing_references() {
        let (mut app, tmp) = audit_app();
        // A document holding two missing references, audited as a load
        // would. A type of its own name, so the registry the other tests in
        // this module filled does not answer for a type this one spelled.
        #[derive(Component, Reflect, Default)]
        #[reflect(Component, Default)]
        struct Latch {
            #[reflect(default)]
            one: Handle<StandardMaterial>,
            #[reflect(default)]
            two: Handle<StandardMaterial>,
        }
        app.register_type::<Latch>();
        write(
            &tmp,
            "zones/hedgerow.bsn",
            &format!(
                "#Zone\n{} {{ one: \"materials/gone.material.bsn\", \
                 two: \"materials/also-gone.material.bsn\" }}\n",
                Latch::type_path()
            ),
        );
        crate::asset_index::rescan_asset_index(app.world_mut());
        let ast = jackdaw_bsn::parse_bsn_text(
            &std::fs::read_to_string(tmp.path().join("assets/zones/hedgerow.bsn"))
                .expect("the scene reads"),
        )
        .expect("the scene parses");
        app.world_mut()
            .get_resource_or_init::<OperatorWarnings>()
            .0
            .clear();
        warn_on_load(app.world_mut(), Path::new("zones/hedgerow.bsn"), &ast);
        let warnings = app
            .world()
            .get_resource::<OperatorWarnings>()
            .map(|warnings| warnings.0.to_vec())
            .unwrap_or_default();
        assert_eq!(
            warnings.len(),
            1,
            "one summary line, not a line per field: {warnings:?}"
        );
        assert!(
            warnings[0].contains("2 references name files"),
            "the line counts what it found: {warnings:?}"
        );
    }

    /// The save boundary warns when an `Entity` field points outside the
    /// document (N6): a dangling id is written as-is, and a reload points it
    /// by spawn order.
    #[test]
    fn a_dangling_entity_field_warns_once_at_the_save_boundary() {
        let mut app = App::new();
        app.add_plugins(bevy::app::TaskPoolPlugin::default());
        app.register_type::<Wire>();
        let alpha = app.world_mut().spawn(Name::new("Alpha")).id();
        let beta = app.world_mut().spawn(Name::new("Beta")).id();
        app.world_mut()
            .entity_mut(alpha)
            .insert(Wire { target: beta });

        // The document holds both entities; nothing dangles.
        let mut ast = jackdaw_bsn::SceneBsnAst::default();
        for entity in [alpha, beta] {
            let node = ast.create_entity_node(vec![]);
            ast.link(entity, node);
            ast.add_to_roots(node);
        }
        app.world_mut().insert_resource(ast);
        app.world_mut()
            .get_resource_or_init::<OperatorWarnings>()
            .0
            .clear();
        warn_on_dangling_entity_fields(app.world_mut());
        let quiet = app
            .world()
            .get_resource::<OperatorWarnings>()
            .map(|warnings| warnings.0.to_vec())
            .unwrap_or_default();
        assert!(
            quiet.is_empty(),
            "a field pointing inside the document costs nothing: {quiet:?}"
        );

        // Beta despawns; the field it was named for dangles.
        app.world_mut().entity_mut(beta).despawn();
        app.world_mut()
            .get_resource_or_init::<OperatorWarnings>()
            .0
            .clear();
        warn_on_dangling_entity_fields(app.world_mut());
        let warnings = app
            .world()
            .get_resource::<OperatorWarnings>()
            .map(|warnings| warnings.0.to_vec())
            .unwrap_or_default();
        assert_eq!(
            warnings.len(),
            1,
            "one warning, naming what it found: {warnings:?}"
        );
        assert!(
            warnings[0].contains("1 Entity fields point outside"),
            "the warning counts the dangling field: {warnings:?}"
        );
    }
}
