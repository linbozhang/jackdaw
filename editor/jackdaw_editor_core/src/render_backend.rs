//! Which wgpu backend the *editor process* renders with.
//!
//! Windows defaults to DX12: the OpenGL driver (`nvoglv64.dll`) has taken
//! the editor down with it before, and DX12 is the native API there.
//! `WGPU_BACKEND` still wins when set, so a diagnostics run can compare
//! backends side by side (`WGPU_BACKEND=vulkan jackdaw`). Games the editor
//! scaffolds or exports assemble their own `DefaultPlugins` in the
//! project, so they keep wgpu's own backend default; this module only
//! runs in the editor process.
//!
//! [`wgpu_settings`] folds the choice into the `WgpuSettings` the editor's
//! `RenderPlugin` is built from in [`crate::launch`].

use bevy::render::settings::{Backends, WgpuSettings};

/// The backends the editor should request, given what `WGPU_BACKEND`
/// parsed to.
///
/// - A set holding at least one backend returns `None`: leave
///   `WgpuSettings::default()` alone, which already applies the variable,
///   including the per-backend tuning Bevy derives from it (validation
///   flags, shader compiler). Overriding here would drop that tuning.
/// - A value whose every token was unknown parses to the empty set (a
///   typo like `WGPU_BACKEND=vukan`, say); wgpu has already warned, and
///   honoring it would leave the editor with no adapter at all. Fall back
///   to the platform default, as if the variable were unset.
/// - An unset variable takes the platform default: DX12 on Windows, and
///   no override anywhere else, so other platforms launch exactly as
///   they always have.
fn backends(from_env: Option<Backends>) -> Option<Backends> {
    let platform_default = || cfg!(windows).then_some(Backends::DX12);
    match from_env {
        Some(backends) if !backends.is_empty() => None,
        _ => platform_default(),
    }
}

/// The `WgpuSettings` the editor's `RenderPlugin` is built from.
///
/// Outside the backend choice this stays `WgpuSettings::default()`, plus
/// the GPU timestamp features a `JACKDAW_RENDER_DIAGNOSTICS` run has to
/// request before the device exists.
pub fn wgpu_settings() -> WgpuSettings {
    let mut settings = WgpuSettings::default();
    if let Some(backends) = backends(Backends::from_env()) {
        settings.backends = Some(backends);
    }
    if let Some(features) = crate::render_diagnostics::timestamp_features() {
        settings.features |= features;
    }
    settings
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `backends` dispatches on the shapes wgpu's env parsing produces:
    /// an unset variable is `None`, a value with no valid backend name in
    /// it is `Some(empty)`.
    #[test]
    fn wgpu_env_parsing_matches_the_shapes_we_dispatch_on() {
        assert_eq!(Backends::from_comma_list("vulkan"), Backends::VULKAN);
        assert_eq!(Backends::from_comma_list("D3D12"), Backends::DX12);
        assert_eq!(
            Backends::from_comma_list("gl, dx12"),
            Backends::GL | Backends::DX12
        );
        assert!(Backends::from_comma_list("vukan").is_empty());
    }

    #[test]
    fn an_unset_variable_takes_the_platform_default() {
        if cfg!(windows) {
            assert_eq!(backends(None), Some(Backends::DX12));
        } else {
            assert_eq!(
                backends(None),
                None,
                "other platforms keep wgpu's own default"
            );
        }
    }

    #[test]
    fn a_valid_variable_is_honored_not_overridden() {
        // `None` means "leave WgpuSettings::default() alone", which is
        // what applies the variable -- together with Bevy's per-backend
        // tuning of it.
        assert_eq!(backends(Some(Backends::VULKAN)), None);
        assert_eq!(backends(Some(Backends::GL | Backends::VULKAN)), None);
        // A set no adapter on this machine can satisfy is still the
        // user's explicit ask; wgpu gets to report that failure.
        assert_eq!(backends(Some(Backends::METAL)), None);
    }

    #[test]
    fn a_value_of_only_unknown_names_falls_back_like_an_unset_one() {
        assert_eq!(backends(Some(Backends::empty())), backends(None));
    }
}
