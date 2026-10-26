//! Config assets as the initial values of game Resources.
//!
//! A game's global tuning parameters — gravity, move speed, player
//! health — live in an authored asset file (created and edited in the
//! editor like any other asset), and arrive in the running game as the
//! initial value of a Resource: one line in the game's plugin,
//!
//! ```ignore
//! app.add_plugins(ConfigPlugin::<GameConfig>::new("game-config.bsn"));
//! ```
//!
//! The file loads through the same startup walk as every other `.bsn`
//! (the [`JackdawPlugin`](crate::JackdawPlugin) catalog), so the
//! editor's Play, a plain `cargo run`, and an exported build all read
//! the same file — the file is the truth, there is no env variable or
//! protocol involved.
//!
//! This is the *initial* value, applied once per process when the
//! startup walk has loaded the asset. Editing the asset while the game
//! runs does not re-inject (live tuning is a later feature); edit the
//! file, stop, play again.
//!
//! The companion pattern: a type that is both an `Asset` (so the
//! editor can author files of it) and a `Resource` (so systems can
//! read it),
//!
//! ```ignore
//! #[derive(Asset, Resource, Reflect, Default, Clone)]
//! #[reflect(Resource, Default)]
//! pub struct GameConfig { pub gravity: f32 }
//! ```
//!
//! registered with `init_asset::<GameConfig>()` and
//! `register_asset_reflect::<GameConfig>()` in the same plugin, so the
//! editor's New Asset menu offers it.
//!
//! A missing file is not an error: the Resource is inserted with
//! `T::default()` and one warning says so, because a game must still
//! run before anyone has authored its config.
//!
//! [`ConfigPlugin`] requires [`crate::JackdawPlugin`] (it reads the
//! catalog the plugin's startup walk fills).

use std::marker::PhantomData;

use bevy::prelude::*;

/// The path a [`ConfigLoader`] watches when the game does not name one:
/// `game-config.bsn` under the asset root.
pub const DEFAULT_CONFIG_PATH: &str = "game-config.bsn";

/// Set when the startup asset walk has finished filing what it found:
/// from here on, a path [`JackdawCatalog`](crate::JackdawCatalog) does
/// not answer is a file that does not exist, not one still loading —
/// the signal a [`ConfigLoader`] waits for before falling back.
#[derive(Resource, Default)]
pub struct AssetsWalked;

/// A game's request for one config asset to become the initial value of
/// its Resource. Spawned by [`ConfigPlugin`], or directly when a game
/// wants [`apply_config_defaults`] registered on its own schedule.
///
/// The loader despawns itself once the value has been applied — the
/// injection is once per process by construction.
#[derive(Component)]
pub struct ConfigLoader<T> {
    /// The asset to load, relative to the asset root — the catalog key
    /// the startup walk files it under (its path, like
    /// `game-config.bsn`), or its `@Name`.
    pub path: String,
    marker: PhantomData<fn() -> T>,
}

impl<T> ConfigLoader<T> {
    /// Watch `path` for the config asset whose value becomes `T`'s
    /// Resource.
    pub fn new(path: impl Into<String>) -> Self {
        Self {
            path: path.into(),
            marker: PhantomData,
        }
    }
}

impl<T> Default for ConfigLoader<T> {
    /// The conventional [`DEFAULT_CONFIG_PATH`], so
    /// `ConfigLoader::<T>::default()` is the sugar for games that keep
    /// the agreed name.
    fn default() -> Self {
        Self::new(DEFAULT_CONFIG_PATH)
    }
}

/// [`ConfigLoader`] plus the system that applies it, in one plugin: the
/// one line a game adds for each config type it wants.
///
/// Spawns the loader immediately (in the plugin's build, before the
/// first frame) and registers [`apply_config_defaults`] on `Update`;
/// the injection happens on the first update after the startup walk
/// has loaded the asset.
pub struct ConfigPlugin<T> {
    /// The asset to load, relative to the asset root.
    pub path: String,
    marker: PhantomData<fn() -> T>,
}

impl<T> ConfigPlugin<T> {
    /// Load `path` as the initial value of `T`'s Resource.
    pub fn new(path: impl Into<String>) -> Self {
        Self {
            path: path.into(),
            marker: PhantomData,
        }
    }
}

impl<T: Asset + Resource + Clone + Default> Default for ConfigPlugin<T> {
    /// The conventional [`DEFAULT_CONFIG_PATH`].
    fn default() -> Self {
        Self::new(DEFAULT_CONFIG_PATH)
    }
}

impl<T: Asset + Resource + Clone + Default> Plugin for ConfigPlugin<T> {
    fn build(&self, app: &mut App) {
        // The default goes in immediately, so a system reading `T`
        // never races the injection: by the first update after startup
        // the walk has loaded the asset and the loader below has
        // replaced the default with the file's value.
        app.insert_resource(T::default());
        app.add_systems(Update, apply_config_defaults::<T>);
        app.world_mut()
            .spawn(ConfigLoader::<T>::new(self.path.clone()));
    }
}

/// Apply every [`ConfigLoader<T>`]'s asset as the initial value of the
/// `T` Resource, once per loader: the loader despawns when done, so a
/// later edit of the loaded asset does not re-inject.
///
/// The asset comes from the [`JackdawCatalog`](crate::JackdawCatalog)
/// the startup walk filled, so this runs only after that walk (the
/// [`AssetsWalked`] it leaves behind). A path the catalog does not
/// answer — a missing file, or one holding another type — becomes
/// `T::default()` with one warning: a missing config must not keep a
/// game from running.
pub fn apply_config_defaults<T: Asset + Resource + Clone + Default>(
    loaders: Query<(Entity, &ConfigLoader<T>)>,
    assets: Res<Assets<T>>,
    catalog: Res<crate::JackdawCatalog>,
    walked: Option<Res<AssetsWalked>>,
    mut commands: Commands,
) {
    let Some(walked) = walked else {
        // No walk yet (or no JackdawPlugin at all): nothing to read,
        // so nothing to decide — the loaders wait.
        return;
    };
    let _ = walked;
    for (entity, loader) in &loaders {
        match catalog
            .get(&loader.path)
            .map(|handle| handle.clone().try_typed::<T>())
        {
            Some(Ok(handle)) => {
                let Some(value) = assets.get(&handle) else {
                    // The walk constructs the value when it files the
                    // handle, so an empty store here means the type
                    // lied about being this asset; treat it as absent.
                    warn!(
                        "config '{}' is present but holds no {} value; starting at the default",
                        loader.path,
                        std::any::type_name::<T>()
                    );
                    commands.insert_resource(T::default());
                    commands.entity(entity).despawn();
                    continue;
                };
                info!(
                    "config '{}' loaded; applying it as {}'s initial value",
                    loader.path,
                    std::any::type_name::<T>()
                );
                commands.insert_resource(value.clone());
                commands.entity(entity).despawn();
            }
            Some(Err(error)) => {
                warn!(
                    "config '{}' cannot serve as {} ({error}); starting at the default",
                    loader.path,
                    std::any::type_name::<T>()
                );
                commands.insert_resource(T::default());
                commands.entity(entity).despawn();
            }
            None => {
                // Only after the walk has it settled is an absent key a
                // missing file rather than a not-yet-loaded one.
                warn!(
                    "no config asset at '{}'; {} starts at its default",
                    loader.path,
                    std::any::type_name::<T>()
                );
                commands.insert_resource(T::default());
                commands.entity(entity).despawn();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A config type in the shape a game would declare it.
    #[derive(Asset, Resource, Reflect, Clone, Default, PartialEq, Debug)]
    #[reflect(Resource, Default)]
    struct TestConfig {
        player_health: f32,
        move_speed: f32,
        gravity: f32,
    }

    /// The editor's on-disk form of a config asset: the header names the
    /// type (what `write_asset_file` writes and the walk reads at a
    /// glance), then the `#Name` patch and the struct patch. The name
    /// carries a `-`, so the emitter quotes it — the exact bytes the
    /// editor writes, pinned here so the editor's writer and the game's
    /// reader cannot drift apart silently.
    fn editor_written_config() -> String {
        let type_path = std::any::type_name::<TestConfig>();
        format!(
            "// jackdaw asset {type_path}\n\
             #\"game-config\"\n\
             {type_path} {{\n    \
                 player_health: 150.0,\n    \
                 move_speed: 2.5,\n    \
                 gravity: -19.5,\n\
             }}\n"
        )
    }

    /// A minimal headless app with the test config type registered, and
    /// the config system either added (the feature) or not (the "before"
    /// half of the red/green pair). The startup walk runs by hand, the
    /// way `JackdawPlugin`'s does.
    fn app_with_assets(with_system: bool) -> App {
        let mut app = App::new();
        app.add_plugins((
            bevy::app::TaskPoolPlugin::default(),
            bevy::asset::AssetPlugin::default(),
        ));
        app.init_asset::<TestConfig>()
            .register_asset_reflect::<TestConfig>();
        app.init_resource::<crate::JackdawCatalog>();
        if with_system {
            app.add_systems(Update, apply_config_defaults::<TestConfig>);
        }
        app
    }

    /// What the plugin's startup step does: file every asset under
    /// `root` into the catalog and the store.
    fn walk(app: &mut App, root: &std::path::Path) {
        crate::load_walked_assets(app.world_mut(), root, None);
    }

    fn temp_project(name: &str) -> std::path::PathBuf {
        let root =
            std::env::temp_dir().join(format!("jackdaw-config-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        root
    }

    /// Pump the app until the condition holds or the frame budget runs
    /// out: the file asset source loads on the app's own task pool, so
    /// "loaded" lands a few frames in.
    fn run_until(app: &mut App, mut done: impl FnMut(&mut App) -> bool, frames: usize) -> bool {
        for _ in 0..frames {
            app.update();
            if done(app) {
                return true;
            }
        }
        false
    }

    /// The red/green pair in one test: without the system the Resource
    /// never exists (the red half — the state of every game before it
    /// opts in, and of the Resources panel's session edits, which no
    /// game process ever sees); with it, the authored file's values
    /// arrive as the Resource's initial value.
    #[test]
    fn a_config_asset_becomes_the_resource_initial_value() {
        let root = temp_project("inject");
        std::fs::write(root.join("game-config.bsn"), editor_written_config()).unwrap();

        let mut before = app_with_assets(false);
        before
            .world_mut()
            .spawn(ConfigLoader::<TestConfig>::default());
        walk(&mut before, &root);
        run_until(
            &mut before,
            |app| app.world().get_resource::<TestConfig>().is_some(),
            5,
        );
        assert!(
            before.world().get_resource::<TestConfig>().is_none(),
            "the red half: without the system no Resource ever appears"
        );

        let mut app = app_with_assets(true);
        app.world_mut().spawn(ConfigLoader::<TestConfig>::default());
        walk(&mut app, &root);
        let applied = run_until(
            &mut app,
            |app| app.world().get_resource::<TestConfig>().is_some(),
            5,
        );
        let config = app.world().get_resource::<TestConfig>().expect("applied");
        assert_eq!(
            config,
            &TestConfig {
                player_health: 150.0,
                move_speed: 2.5,
                gravity: -19.5,
            },
            "the green half: the file's values are the initial value"
        );
        assert!(applied, "the injection happened within the budget");
        let _ = std::fs::remove_dir_all(&root);
    }

    /// A missing file is the default plus one warning, and the loader
    /// retires — the game runs, and it does not warn every frame.
    #[test]
    fn a_missing_config_falls_back_to_default_once() {
        let root = temp_project("missing");

        let mut app = app_with_assets(true);
        app.world_mut().spawn(ConfigLoader::<TestConfig>::default());
        walk(&mut app, &root);
        let applied = run_until(
            &mut app,
            |app| app.world().get_resource::<TestConfig>().is_some(),
            5,
        );
        assert!(applied, "the fallback applies within the budget");
        assert_eq!(
            app.world().get_resource::<TestConfig>(),
            Some(&TestConfig::default()),
            "a game without a config file still runs, at the default"
        );
        let mut loaders = app.world_mut().query::<&ConfigLoader<TestConfig>>();
        assert!(
            loaders.iter(app.world()).next().is_none(),
            "the loader is gone: one application per process by construction"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The injection is once per process: editing the asset in the
    /// store after it applied does not change the running Resource.
    #[test]
    fn a_later_edit_of_the_asset_does_not_re_inject() {
        let root = temp_project("once");
        std::fs::write(root.join("game-config.bsn"), editor_written_config()).unwrap();

        let mut app = app_with_assets(true);
        app.world_mut().spawn(ConfigLoader::<TestConfig>::default());
        walk(&mut app, &root);
        run_until(
            &mut app,
            |app| app.world().get_resource::<TestConfig>().is_some(),
            5,
        );

        // What a hot-reload (a later feature) would do: the asset's
        // value changes under the running game.
        let mut store = app.world_mut().resource_mut::<Assets<TestConfig>>();
        for (_, asset) in store.iter_mut() {
            asset.move_speed = 99.0;
        }
        for _ in 0..10 {
            app.update();
        }
        assert_eq!(
            app.world().get_resource::<TestConfig>().unwrap().move_speed,
            2.5,
            "the initial value stands until the next process"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The plugin puts the default in during its build, so a system
    /// reading `T` never races the injection — the resource exists
    /// before the first update, at the default, and the file's value
    /// replaces it on the first update after the walk.
    #[test]
    fn the_plugin_has_the_resource_ready_before_the_first_update() {
        let root = temp_project("ready");
        std::fs::write(root.join("game-config.bsn"), editor_written_config()).unwrap();

        let mut app = App::new();
        app.add_plugins((
            bevy::app::TaskPoolPlugin::default(),
            bevy::asset::AssetPlugin::default(),
        ));
        app.init_asset::<TestConfig>()
            .register_asset_reflect::<TestConfig>();
        app.init_resource::<crate::JackdawCatalog>();
        app.add_plugins(ConfigPlugin::<TestConfig>::default());
        // No update yet — and the resource is already there.
        assert_eq!(
            app.world().get_resource::<TestConfig>(),
            Some(&TestConfig::default()),
            "the default is in before the first frame, so consumers cannot panic"
        );
        walk(&mut app, &root);
        run_until(
            &mut app,
            |app| {
                app.world()
                    .get_resource::<TestConfig>()
                    .is_some_and(|config| config.move_speed == 2.5)
            },
            5,
        );
        assert_eq!(
            app.world().get_resource::<TestConfig>().unwrap().move_speed,
            2.5,
            "the file's value replaces the default once the walk has run"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The config file is read from the asset root the game was given —
    /// the editor's Play points that at the project, so the PIE temp
    /// copies under `.jackdaw-pie/` (which hold scene copies, never
    /// configs) leave the config's real file alone: the value applied
    /// is the one in `assets/`, even with a temp scene beside it.
    #[test]
    fn a_pie_temp_directory_does_not_shadow_the_config() {
        let root = temp_project("pie");
        std::fs::write(root.join("game-config.bsn"), editor_written_config()).unwrap();
        // The shape a Play session leaves while it runs: a temp copy of
        // the scene under the PIE directory.
        std::fs::create_dir_all(root.join(".jackdaw-pie")).unwrap();
        std::fs::write(root.join(".jackdaw-pie/current.bsn"), "scene junk").unwrap();

        let mut app = app_with_assets(true);
        app.world_mut().spawn(ConfigLoader::<TestConfig>::default());
        walk(&mut app, &root);
        run_until(
            &mut app,
            |app| app.world().get_resource::<TestConfig>().is_some(),
            5,
        );
        assert_eq!(
            app.world().get_resource::<TestConfig>().unwrap().move_speed,
            2.5,
            "the config still comes from its own file, not the temp tree"
        );
        let _ = std::fs::remove_dir_all(&root);
    }
}
