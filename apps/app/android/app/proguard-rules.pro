# R8/ProGuard rules for the Android release build.
#
# Flutter's Gradle plugin supplies the engine/embedding keep rules itself, and
# the Rust core is a native .so (untouched by R8). Plugin-specific keeps go
# here if a release build ever hits ClassNotFound after shrinking.
