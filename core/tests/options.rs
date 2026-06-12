//! Tests for the public options surface: the string `parse` helpers every
//! binding relies on, the defaults, the shared `OptionsDto` mapping, and the
//! error Display impl.

use alotno_core::{
    ColorMode, ConvertError, CurveType, DrawStyle, GroupBy, OptionsDto, Preset, Stacking,
    SvgOptions, SvgVersion, WebpOptions,
};

#[test]
fn preset_parse_accepts_ui_wordings() {
    assert_eq!(Preset::parse("low"), Preset::Low);
    assert_eq!(Preset::parse("coarse"), Preset::Low);
    assert_eq!(Preset::parse("medium"), Preset::Medium);
    assert_eq!(Preset::parse("ULTRA"), Preset::Ultra);
    assert_eq!(Preset::parse("super fine"), Preset::Ultra);
    assert_eq!(Preset::parse("superfine"), Preset::Ultra);
    assert_eq!(Preset::parse("anything-else"), Preset::High);
}

#[test]
fn color_mode_parse() {
    assert_eq!(ColorMode::parse("posterized"), ColorMode::Posterized);
    assert_eq!(ColorMode::parse("color"), ColorMode::Posterized);
    assert_eq!(ColorMode::parse("mono"), ColorMode::Mono);
    assert_eq!(ColorMode::parse(""), ColorMode::Mono);
}

#[test]
fn curve_type_parse() {
    assert_eq!(CurveType::parse("lines"), CurveType::Lines);
    assert_eq!(CurveType::parse("polygon"), CurveType::Lines);
    assert_eq!(CurveType::parse("curves"), CurveType::Curves);
    assert_eq!(CurveType::parse("?"), CurveType::Curves);
}

#[test]
fn stacking_parse() {
    assert_eq!(Stacking::parse("stacked"), Stacking::Stacked);
    assert_eq!(Stacking::parse("cutouts"), Stacking::Cutouts);
    assert_eq!(Stacking::parse(""), Stacking::Cutouts);
}

#[test]
fn svg_version_parse() {
    assert_eq!(SvgVersion::parse("1.0"), SvgVersion::V1_0);
    assert_eq!(SvgVersion::parse("10"), SvgVersion::V1_0);
    assert_eq!(SvgVersion::parse("tiny"), SvgVersion::Tiny1_2);
    assert_eq!(SvgVersion::parse("1.2"), SvgVersion::Tiny1_2);
    assert_eq!(SvgVersion::parse("1.1"), SvgVersion::V1_1);
    assert_eq!(SvgVersion::parse("x"), SvgVersion::V1_1);
}

#[test]
fn draw_style_and_group_by_parse() {
    assert_eq!(DrawStyle::parse("stroke"), DrawStyle::Stroke);
    assert_eq!(DrawStyle::parse("both"), DrawStyle::Both);
    assert_eq!(DrawStyle::parse("fill"), DrawStyle::Fill);
    assert_eq!(GroupBy::parse("color"), GroupBy::Color);
    assert_eq!(GroupBy::parse("none"), GroupBy::None);
}

#[test]
fn defaults_are_the_documented_ones() {
    let svg = SvgOptions::default();
    assert_eq!(svg.preset, Preset::High);
    assert_eq!(svg.color_mode, ColorMode::Mono);
    assert_eq!(svg.posterize_steps, 4);
    assert_eq!(svg.threshold, 128);
    assert_eq!(svg.stroke.color.as_deref(), Some("#000000"));
    assert!((svg.stroke.width - 1.0).abs() < f32::EPSILON);

    let webp = WebpOptions::default();
    assert!(!webp.lossless);
    assert!(!webp.grayscale);
    assert!((webp.quality - 82.0).abs() < f32::EPSILON);
}

#[test]
fn options_dto_maps_to_svg_options() {
    let dto = OptionsDto {
        preset: "ultra".into(),
        color_mode: "posterized".into(),
        curve_type: "lines".into(),
        stacking: "stacked".into(),
        posterize_steps: 6,
        threshold: 200,
        version: "tiny".into(),
        draw_style: "both".into(),
        group_by: "color".into(),
        stroke_color: "#ff0000".into(),
        stroke_width: 2.5,
        non_scaling_stroke: true,
        fixed_size: true,
        adobe_compat: true,
        clip_overflow: true,
    };
    let o: SvgOptions = dto.into();
    assert_eq!(o.preset, Preset::Ultra);
    assert_eq!(o.color_mode, ColorMode::Posterized);
    assert_eq!(o.curve_type, CurveType::Lines);
    assert_eq!(o.stacking, Stacking::Stacked);
    assert_eq!(o.posterize_steps, 6);
    assert_eq!(o.threshold, 200);
    assert_eq!(o.version, SvgVersion::Tiny1_2);
    assert_eq!(o.draw_style, DrawStyle::Both);
    assert_eq!(o.group_by, GroupBy::Color);
    assert_eq!(o.stroke.color.as_deref(), Some("#ff0000"));
    assert!(o.stroke.non_scaling);
    assert!(o.fixed_size && o.adobe_compat && o.clip_overflow);
}

#[test]
fn dto_empty_stroke_color_means_keep_traced_color() {
    let dto = OptionsDto {
        stroke_color: "   ".into(),
        ..OptionsDto::default()
    };
    let o: SvgOptions = dto.into();
    assert_eq!(o.stroke.color, None);
}

#[test]
fn dto_default_matches_svg_options_default() {
    let from_dto: SvgOptions = OptionsDto::default().into();
    let plain = SvgOptions::default();
    assert_eq!(from_dto.preset, plain.preset);
    assert_eq!(from_dto.color_mode, plain.color_mode);
    assert_eq!(from_dto.threshold, plain.threshold);
    assert_eq!(from_dto.stroke.color, plain.stroke.color);
}

#[test]
fn convert_error_display_is_descriptive() {
    assert!(ConvertError::InvalidInput("too big".into())
        .to_string()
        .contains("too big"));
    assert!(ConvertError::Decode("bad png".into())
        .to_string()
        .contains("decode"));
    assert!(ConvertError::Trace("no trace".into())
        .to_string()
        .contains("trace"));
    assert!(ConvertError::Encode("no enc".into())
        .to_string()
        .contains("encode"));
}
