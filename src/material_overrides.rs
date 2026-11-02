//! Authoring the materials a placed model's parts wear in place of their own,
//! and telling the author when an override stops being able to.

use std::collections::{BTreeMap, HashSet};

use bevy::gltf::GltfMaterialName;
use bevy::prelude::*;
use jackdaw_api::prelude::*;
use jackdaw_bsn::BsnProjectAssets;
use jackdaw_commands::CommandHistory;
use jackdaw_runtime::JackdawCatalog;
use jackdaw_scene_types::{GltfSource, InstanceMaterialOverrides, MaterialOverrides};

use crate::commands::EditorCommand;
use crate::selection::Selection;

const MODEL_OVERRIDES_TYPE_PATH: &str = "jackdaw_scene_types::types::MaterialOverrides";
const INSTANCE_OVERRIDES_TYPE_PATH: &str = "jackdaw_scene_types::types::InstanceMaterialOverrides";
const GLTF_SOURCE_TYPE_PATH: &str = "jackdaw_scene_types::types::GltfSource";

/// Whether a field of a component of `type_path` names an asset by path even
/// though its type is a plain string: the two override types hold their
/// references as the values of their `materials` map, and a placed model's
/// own `GltfSource` names its model file. The audit's findings and the rename
/// rewrite both read this list, the same way they read a prefab instance's
/// `IsA.source` — one field being a reference whatever its type.
pub(crate) fn takes_string_path(type_path: &str, field: &str) -> bool {
    (matches!(
        type_path,
        MODEL_OVERRIDES_TYPE_PATH | INSTANCE_OVERRIDES_TYPE_PATH
    ) && field == "materials")
        || (type_path == GLTF_SOURCE_TYPE_PATH && field == "path")
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<MaterialOverrideOp>();
}

/// The editor-side report of the failures an override can no longer hide.
/// The twin of the runtime's `find_models_to_dress`: the same trigger set (an
/// override changed or removed, a part arriving, the project reference tables
/// moving), but read-only — instead of dressing the parts it compares each
/// holder's entries against the names the parts under it wear and the
/// materials the project resolves, and says once which entries fail. It lives
/// on the editor side so the warnings stay out of a game process's log, and
/// the status bar is editor chrome the runtime cannot reach; the audit's
/// findings (`takes_string_path` feeds those too) are the discoverability
/// half of the same story.
pub(crate) fn plugin(app: &mut App) {
    app.init_resource::<ReportedOverrides>().add_systems(
        Update,
        report_broken_overrides.run_if(in_state(crate::AppState::Editor)),
    );
}

/// The override failures a report went out for during this session, keyed by
/// the holder and the identity of the failure. One warning per failure,
/// however many frames it lasts; a holder's locks clear themselves while it
/// is being judged (an entry that fails no more is dropped), so a failure
/// that comes back speaks again and an undo restoring a sound map stays
/// quiet — the same rule `asset_failures` keeps for failed loads, with the
/// lock changing shape instead of files.
#[derive(Resource, Default)]
pub struct ReportedOverrides(HashSet<(Entity, String)>);

impl ReportedOverrides {
    /// How many failures are on record. The tests count them, since a quiet
    /// second report looks exactly like a loud one.
    #[cfg(test)]
    fn len(&self) -> usize {
        self.0.len()
    }
}

/// One failure an override entry suffers, computed per holder.
struct BrokenEntry {
    /// The override entry's material name.
    key: String,
    /// The material asset path the entry spells.
    path: String,
    /// No part under the holder wears this name any more: a GLB reimport
    /// renamed or removed the material. The only other failure an entry can
    /// suffer — the name worn but no material answering to the path — is
    /// what's left when this is false.
    stale_name: bool,
}

impl BrokenEntry {
    /// What one report is filed under, so the same failure warns once: the
    /// name when that is what broke, the file when the name still matches.
    fn identity(&self) -> String {
        if self.stale_name {
            format!("name:{}", self.key)
        } else {
            format!("file:{}", self.path)
        }
    }

    fn line(&self, who: &str) -> String {
        if self.stale_name {
            format!(
                "material override: {who} overrides a material named '{}', which no part of it \
                 wears any more -- its parts wear their own material until the name returns",
                self.key
            )
        } else {
            format!(
                "material override: {who} overrides '{}' with '{}', which names no material the \
                 project holds -- its parts wear their own material until it returns",
                self.key, self.path
            )
        }
    }
}

/// The failures the overrides on `holder` suffer: an entry whose material
/// name no part under it wears, and an entry whose path names no material the
/// project holds. The resolutions are the dressing's own
/// (`material_of_reference`), so what reads as broken here is exactly what
/// will not dress. A name that is gone is the failure reported; the health of
/// its path is moot until the name returns.
fn broken_entries(world: &World, holder: Entity) -> Vec<BrokenEntry> {
    let mut materials: BTreeMap<String, String> = world
        .get::<MaterialOverrides>(holder)
        .map(|overrides| overrides.materials.clone())
        .unwrap_or_default();
    if let Some(overrides) = world.get::<InstanceMaterialOverrides>(holder) {
        materials.extend(
            overrides
                .materials
                .iter()
                .map(|(key, path)| (key.clone(), path.clone())),
        );
    }
    if materials.is_empty() {
        return Vec::new();
    }
    let worn: HashSet<String> = model_material_names(world, holder).into_iter().collect();
    materials
        .iter()
        .filter_map(|(key, path)| {
            let stale_name = !worn.contains(key);
            let unresolved_path =
                !stale_name && jackdaw_runtime::material_of_reference(world, path).is_none();
            (stale_name || unresolved_path).then_some(BrokenEntry {
                key: key.clone(),
                path: path.clone(),
                stale_name,
            })
        })
        .collect()
}

/// Compare every holder whose world just moved against the parts it holds,
/// warning once per failing entry. The trigger set is `find_models_to_dress`'s
/// (the runtime dressing); keep the two lists moving together.
fn report_broken_overrides(
    changed: Query<
        Entity,
        Or<(
            Changed<MaterialOverrides>,
            Changed<InstanceMaterialOverrides>,
        )>,
    >,
    new_parts: Query<Entity, Added<GltfMaterialName>>,
    holders: Query<Entity, Or<(With<MaterialOverrides>, With<InstanceMaterialOverrides>)>>,
    parents: Query<&ChildOf>,
    mut removed: RemovedComponents<MaterialOverrides>,
    mut removed_instance: RemovedComponents<InstanceMaterialOverrides>,
    project: Option<Res<BsnProjectAssets>>,
    catalog: Option<Res<JackdawCatalog>>,
    mut commands: Commands,
) {
    let mut examine: HashSet<Entity> = changed.iter().collect();
    // A holder whose overrides left has nothing left to say; judging it
    // clears the locks it held.
    examine.extend(removed.read());
    examine.extend(removed_instance.read());
    // A part arriving can retire a stale entry's report (the name came
    // back): every holder it hangs under is judged again.
    for part in new_parts.iter() {
        let mut at = Some(part);
        while let Some(entity) = at {
            if holders.contains(entity) {
                examine.insert(entity);
            }
            at = parents.get(entity).ok().map(ChildOf::parent);
        }
    }
    // The reference tables moved (files loaded, moved, healed): every
    // holder's unresolved entries are judged again, and an entry whose file
    // arrived stops being reported the same quiet way the dressing re-wears
    // it.
    if project.is_some_and(|project| project.is_changed())
        || catalog.is_some_and(|catalog| catalog.is_changed())
    {
        examine.extend(holders.iter());
    }
    if examine.is_empty() {
        return;
    }
    let examine: Vec<Entity> = examine.into_iter().collect();
    commands.queue(move |world: &mut World| {
        for holder in examine {
            let entries = broken_entries(world, holder);
            // This holder's locks clear themselves while it is judged: one
            // that no longer names a current failure is dropped, so a
            // failure that comes back speaks again, and an undo restoring
            // the same map is quiet — the same entries judged, all on
            // record.
            let fresh: Vec<BrokenEntry> = {
                let mut reported = world.resource_mut::<ReportedOverrides>();
                reported.0.retain(|(entity, identity)| {
                    *entity != holder || entries.iter().any(|entry| entry.identity() == *identity)
                });
                let mut fresh = Vec::new();
                for entry in entries {
                    if reported.0.insert((holder, entry.identity())) {
                        fresh.push(entry);
                    }
                }
                fresh
            };
            if fresh.is_empty() {
                continue;
            }
            let who = world
                .get::<Name>(holder)
                .map(Name::as_str)
                .unwrap_or("a model")
                .to_string();
            for entry in fresh {
                warn!("{}", entry.line(&who));
                crate::status_bar::notify_warn(world, entry.line(&who));
            }
        }
    });
}

/// The placed model `entity` belongs to: itself, its nearest model ancestor, or the one model under it.
pub fn model_root(world: &World, entity: Entity) -> Option<Entity> {
    let mut at = entity;
    loop {
        if world.get::<GltfSource>(at).is_some() {
            return Some(at);
        }
        match world.get::<ChildOf>(at) {
            Some(parent) => at = parent.parent(),
            None => break,
        }
    }
    let mut models = Vec::new();
    let mut open = vec![entity];
    while let Some(at) = open.pop() {
        if world.get::<GltfSource>(at).is_some() {
            models.push(at);
            continue;
        }
        if let Some(children) = world.get::<Children>(at) {
            open.extend(children.iter());
        }
    }
    match models.as_slice() {
        [model] => Some(*model),
        _ => None,
    }
}

/// The glTF material names the parts under `root` wear, sorted and without repeats.
pub fn model_material_names(world: &World, root: Entity) -> Vec<String> {
    let mut names = Vec::new();
    let mut open = vec![root];
    while let Some(at) = open.pop() {
        if let Some(name) = world.get::<GltfMaterialName>(at) {
            names.push(name.0.clone());
        }
        if let Some(children) = world.get::<Children>(at) {
            open.extend(children.iter());
        }
    }
    names.sort();
    names.dedup();
    names
}

/// Which component an override is written to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum OverrideLayer {
    /// The model's own [`MaterialOverrides`], which a prefab of it carries.
    Model,
    /// The enclosing prefab instance's [`InstanceMaterialOverrides`], laid over the model's.
    Instance,
}

impl OverrideLayer {
    fn type_path(self) -> &'static str {
        match self {
            Self::Model => MODEL_OVERRIDES_TYPE_PATH,
            Self::Instance => INSTANCE_OVERRIDES_TYPE_PATH,
        }
    }

    fn read(self, world: &World, entity: Entity) -> Option<BTreeMap<String, String>> {
        match self {
            Self::Model => world
                .get::<MaterialOverrides>(entity)
                .map(|overrides| overrides.materials.clone()),
            Self::Instance => world
                .get::<InstanceMaterialOverrides>(entity)
                .map(|overrides| overrides.materials.clone()),
        }
    }
}

/// The nearest prefab instance holding `entity`, itself included.
fn enclosing_instance(world: &World, entity: Entity) -> Option<Entity> {
    let mut at = Some(entity);
    while let Some(candidate) = at {
        if world.get::<crate::prefab::IsA>(candidate).is_some() {
            return Some(candidate);
        }
        at = world.get::<ChildOf>(candidate).map(ChildOf::parent);
    }
    None
}

/// One undo entry for a model's material overrides, or its prefab instance's.
pub struct SetMaterialOverrides {
    entity: Entity,
    layer: OverrideLayer,
    before: Option<BTreeMap<String, String>>,
    after: Option<BTreeMap<String, String>>,
}

impl SetMaterialOverrides {
    /// Set `names` on model `root` to `material` (clear when `None`), on its prefab instance if it is in one.
    pub fn new(world: &World, root: Entity, names: &[String], material: Option<&str>) -> Self {
        let (entity, layer) = match enclosing_instance(world, root) {
            Some(instance) => (instance, OverrideLayer::Instance),
            None => (root, OverrideLayer::Model),
        };
        let before = layer.read(world, entity);
        let mut materials = before.clone().unwrap_or_default();
        for name in names {
            match material {
                Some(path) => {
                    materials.insert(name.clone(), path.to_string());
                }
                None => {
                    materials.remove(name);
                }
            }
        }
        let after = (!materials.is_empty()).then_some(materials);
        Self {
            entity,
            layer,
            before,
            after,
        }
    }

    /// Whether running this would change nothing.
    pub fn is_noop(&self) -> bool {
        self.before == self.after
    }

    fn apply(&self, world: &mut World, materials: Option<&BTreeMap<String, String>>) {
        let Ok(mut node) = world.get_entity_mut(self.entity) else {
            return;
        };
        let Some(materials) = materials.cloned() else {
            match self.layer {
                OverrideLayer::Model => node.remove::<MaterialOverrides>(),
                OverrideLayer::Instance => node.remove::<InstanceMaterialOverrides>(),
            };
            if let Some(mut ast) = world.get_resource_mut::<jackdaw_bsn::SceneBsnAst>()
                && let Some(ast_node) = ast.ast_for(self.entity)
            {
                ast.remove_component_patch(ast_node, self.layer.type_path());
            }
            return;
        };
        match self.layer {
            OverrideLayer::Model => {
                let overrides = MaterialOverrides { materials };
                node.insert(overrides.clone());
                crate::commands::sync_component_to_ast(
                    world,
                    self.entity,
                    MODEL_OVERRIDES_TYPE_PATH,
                    &overrides,
                );
            }
            OverrideLayer::Instance => {
                let overrides = InstanceMaterialOverrides { materials };
                node.insert(overrides.clone());
                crate::commands::sync_component_to_ast(
                    world,
                    self.entity,
                    INSTANCE_OVERRIDES_TYPE_PATH,
                    &overrides,
                );
            }
        }
    }
}

impl EditorCommand for SetMaterialOverrides {
    fn execute(&mut self, world: &mut World) {
        self.entity = crate::scene_nodes::live_entity(world, self.entity);
        let after = self.after.clone();
        self.apply(world, after.as_ref());
    }

    fn undo(&mut self, world: &mut World) {
        self.entity = crate::scene_nodes::live_entity(world, self.entity);
        let before = self.before.clone();
        self.apply(world, before.as_ref());
    }

    fn description(&self) -> &str {
        "Material override"
    }
}

/// Set which material a placed model's parts wear in place of their own.
#[operator(
    id = "material.override",
    label = "Override Model Material",
    description = "Make a placed model's parts that wear one of its materials wear a material \
                   asset instead, saved with the scene.",
    allows_undo = false,
    params(
        entity(
            Entity,
            doc = "The placed model, or one of its parts. Defaults to the selected one."
        ),
        name(
            String,
            doc = "The model's material name to replace. Empty replaces every material the model wears."
        ),
        material(
            String,
            doc = "Path of the material asset to wear, e.g. materials/moss.bsn. Empty gives the \
                   model its own material back."
        ),
    )
)]
pub(crate) fn material_override(
    params: In<OperatorParameters>,
    world: &mut World,
) -> OperatorResult {
    let id = "material.override";
    let Some(target) = params
        .as_entity("entity")
        .or_else(|| world.resource::<Selection>().primary())
    else {
        warn_caller(world, format!("{id}: name a placed model or select one"));
        return OperatorResult::Cancelled;
    };
    let Some(root) = model_root(world, target) else {
        warn_caller(
            world,
            format!("{id}: {target} is not a placed model or one of its parts"),
        );
        return OperatorResult::Cancelled;
    };
    let names = match params.as_str("name").filter(|name| !name.is_empty()) {
        Some(name) => vec![name.to_string()],
        None if target != root => match world.get::<GltfMaterialName>(target) {
            // The part wears a named material: that one name.
            Some(name) => vec![name.0.clone()],
            // A part wearing an UNNAMED material can be addressed by no
            // override (the loader names nothing for it). Refusing is the
            // honest answer; expanding silently to the model's every named
            // material let one click retarget the whole model (MO4).
            None => {
                let named = model_material_names(world, root);
                if named.is_empty() {
                    Vec::new() // falls to the no-named-materials refusal below
                } else {
                    warn_caller(
                        world,
                        format!(
                            "{id}: that part wears an unnamed material, which no override can \
                             address; name= one of the materials the model does name: {}",
                            named.join(", ")
                        ),
                    );
                    return OperatorResult::Cancelled;
                }
            }
        },
        None => model_material_names(world, root),
    };
    if names.is_empty() {
        warn_caller(
            world,
            format!("{id}: the model has no named materials yet; name one with name="),
        );
        return OperatorResult::Cancelled;
    }
    let material = params
        .as_str("material")
        .map(str::trim)
        .filter(|path| !path.is_empty());
    if let Some(path) = material
        && jackdaw_runtime::material_of_reference(world, path).is_none()
    {
        warn_caller(
            world,
            format!("{id}: {path} names no material this project holds"),
        );
        return OperatorResult::Cancelled;
    }

    let command = SetMaterialOverrides::new(world, root, &names, material);
    if command.is_noop() {
        return OperatorResult::Finished;
    }
    world.resource_scope(|world, mut history: Mut<CommandHistory>| {
        history.execute(Box::new(command), world);
    });
    OperatorResult::Finished
}

#[cfg(test)]
mod tests {
    use super::*;
    use bevy::ecs::system::RunSystemOnce as _;
    use bevy::platform::collections::HashMap;

    fn a_model(world: &mut World, parts: &[&str]) -> Entity {
        let root = world.spawn_empty().id();
        for name in parts {
            world.spawn((GltfMaterialName((*name).to_string()), ChildOf(root)));
        }
        root
    }

    fn overrides(pairs: &[(&str, &str)]) -> MaterialOverrides {
        MaterialOverrides {
            materials: pairs
                .iter()
                .map(|(name, path)| (name.to_string(), path.to_string()))
                .collect(),
        }
    }

    /// The project resolves `path` to a held standard material.
    fn holds(world: &mut World, path: &str) {
        world.init_resource::<Assets<StandardMaterial>>();
        let handle = world
            .resource_mut::<Assets<StandardMaterial>>()
            .add(StandardMaterial::default())
            .clone()
            .untyped();
        world.insert_resource(BsnProjectAssets(HashMap::from_iter([(
            path.to_string(),
            handle,
        )])));
    }

    fn run(world: &mut World) {
        world
            .run_system_once(report_broken_overrides)
            .expect("the report ran");
    }

    fn notice(world: &mut World) -> String {
        world
            .resource::<crate::status_bar::StatusNotice>()
            .text()
            .to_string()
    }

    fn quiet(world: &mut World) {
        *world.resource_mut::<crate::status_bar::StatusNotice>() = default();
    }

    /// A stale entry — a name no part wears any more — warns once on the
    /// status bar and stays quiet while it lasts, however often the world
    /// makes the report look again.
    #[test]
    fn a_stale_override_warns_once_and_stays_quiet_while_it_lasts() {
        let mut world = World::new();
        world.init_resource::<ReportedOverrides>();
        world.init_resource::<crate::status_bar::StatusNotice>();
        let root = a_model(&mut world, &["Rock"]);
        world.entity_mut(root).insert(Name::new("Cliff"));
        world
            .entity_mut(root)
            .insert(overrides(&[("Boulder", "materials/mossy.bsn")]));

        run(&mut world);

        assert_eq!(
            world.resource::<ReportedOverrides>().len(),
            1,
            "the stale entry is on record"
        );
        let spoken = notice(&mut world);
        assert!(
            spoken.contains("material override")
                && spoken.contains("Boulder")
                && spoken.contains("Cliff"),
            "the status bar names the holder and the failing name: {spoken}"
        );

        // The failure lasts (a reimport changed the overrides again, still
        // stale): judged again, already reported, stays quiet.
        quiet(&mut world);
        world
            .entity_mut(root)
            .insert(overrides(&[("Boulder", "materials/mossy.bsn")]));
        run(&mut world);
        assert_eq!(world.resource::<ReportedOverrides>().len(), 1);
        assert!(
            !world
                .resource::<crate::status_bar::StatusNotice>()
                .is_active(),
            "the same failure does not warn twice"
        );
    }

    /// A stale entry whose name comes back clears its report (a part arrives
    /// wearing the name again), and if the name goes once more it speaks
    /// again rather than staying quiet for the rest of the session.
    #[test]
    fn a_stale_override_that_recovers_clears_its_report_and_speaks_again() {
        let mut world = World::new();
        world.init_resource::<ReportedOverrides>();
        world.init_resource::<crate::status_bar::StatusNotice>();
        holds(&mut world, "materials/mossy.bsn");
        let root = a_model(&mut world, &["Rock"]);
        world
            .entity_mut(root)
            .insert(overrides(&[("Boulder", "materials/mossy.bsn")]));
        run(&mut world);
        assert_eq!(world.resource::<ReportedOverrides>().len(), 1);

        // The reimport brings the name back: a part arrives wearing it.
        let part = world
            .spawn((GltfMaterialName("Boulder".to_string()), ChildOf(root)))
            .id();
        run(&mut world);
        assert_eq!(
            world.resource::<ReportedOverrides>().len(),
            0,
            "the recovered entry's report clears itself"
        );

        // The name goes again (the part loses it, the overrides are judged
        // once more): it speaks again.
        world.entity_mut(part).remove::<GltfMaterialName>();
        world
            .entity_mut(root)
            .insert(overrides(&[("Boulder", "materials/mossy.bsn")]));
        run(&mut world);
        assert_eq!(
            world.resource::<ReportedOverrides>().len(),
            1,
            "a failure that came back speaks again"
        );
    }

    /// A sound override — a name a part wears, a path the project resolves —
    /// is judged and says nothing, however often: an undo restoring the same
    /// map is not a false warning.
    #[test]
    fn a_sound_override_never_warns_even_when_judged_again() {
        let mut world = World::new();
        world.init_resource::<ReportedOverrides>();
        world.init_resource::<crate::status_bar::StatusNotice>();
        holds(&mut world, "materials/mossy.bsn");
        let root = a_model(&mut world, &["Rock"]);
        world
            .entity_mut(root)
            .insert(overrides(&[("Rock", "materials/mossy.bsn")]));

        run(&mut world);
        run(&mut world);

        assert_eq!(world.resource::<ReportedOverrides>().len(), 0);
        assert!(
            !world
                .resource::<crate::status_bar::StatusNotice>()
                .is_active(),
            "a sound override is quiet"
        );
    }

    /// An entry whose name is worn but whose material file is gone warns
    /// once, and stops on its own when the file arrives — the reference
    /// tables moving is the same trigger the dressing re-wears on.
    #[test]
    fn an_override_whose_material_file_is_gone_warns_once_and_stops_when_it_arrives() {
        let mut world = World::new();
        world.init_resource::<ReportedOverrides>();
        world.init_resource::<crate::status_bar::StatusNotice>();
        let root = a_model(&mut world, &["Rock"]);
        world
            .entity_mut(root)
            .insert(overrides(&[("Rock", "materials/late.bsn")]));

        run(&mut world);

        assert_eq!(world.resource::<ReportedOverrides>().len(), 1);
        assert!(
            notice(&mut world).contains("names no material the project holds"),
            "the status bar names the unresolved path"
        );

        // The file arrives: the project resolves it, the report clears
        // itself, and nothing speaks.
        quiet(&mut world);
        holds(&mut world, "materials/late.bsn");
        run(&mut world);
        assert_eq!(
            world.resource::<ReportedOverrides>().len(),
            0,
            "the healed entry's report clears itself"
        );
        assert!(
            !world
                .resource::<crate::status_bar::StatusNotice>()
                .is_active(),
            "no warning for a healed entry"
        );
    }

    /// An instance layer's stale entry is reported the same way the model
    /// layer's is: one rule, whichever component holds the overrides.
    #[test]
    fn an_instance_stale_override_is_reported_too() {
        let mut world = World::new();
        world.init_resource::<ReportedOverrides>();
        world.init_resource::<crate::status_bar::StatusNotice>();
        let model = a_model(&mut world, &["Rock"]);
        let instance = world
            .spawn(InstanceMaterialOverrides {
                materials: [("Gone".to_string(), "materials/mossy.bsn".to_string())]
                    .into_iter()
                    .collect(),
            })
            .add_child(model)
            .id();
        let _ = instance;

        run(&mut world);

        assert_eq!(
            world.resource::<ReportedOverrides>().len(),
            1,
            "the instance's stale entry is on record"
        );
    }
}
