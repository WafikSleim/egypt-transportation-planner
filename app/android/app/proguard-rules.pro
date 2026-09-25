# R8 keep rules for the release build.
#
# This file is deliberately almost empty, and that is a finding rather than an
# omission. All three plugins this app uses - maplibre_gl, geolocator and
# shared_preferences - ship their own *consumer* rules inside their published
# artifacts, and R8 merges those into this configuration automatically. Checked
# on 2026-09-23 against the versions in `pubspec.lock`:
#
#   org.maplibre.gl:android-sdk-opengl:13.5.0   ships `proguard.txt` in the AAR:
#       keeps the Gson types the native renderer reflects on, the enums under
#       `org.maplibre.android.**`, `RenderingStats` and `NativeMapOptions`
#   com.squareup.okhttp3:okhttp                 ships `META-INF/proguard/*.pro`
#   geolocator_android, shared_preferences_android
#                                               pure Flutter plugin shims,
#       reached through GeneratedPluginRegistrant, which is ordinary Java that
#       R8 traces; neither declares `consumerProguardFiles` and neither needs to
#
# Anything reached only from JNI is covered by the default
# `proguard-android-optimize.txt`, which keeps every class declaring a native
# method.
#
# So: do not add speculative `-keep` rules here. A `-keep class org.maplibre.**`
# would silently switch off shrinking for the largest Java dependency in the
# build in exchange for a reassurance nobody has measured.
#
# What is NOT settled: none of this has been seen on a phone. R8 failures do not
# happen at build time - the build is green either way - they happen the first
# time a stripped class is looked up by name, which for the map is the moment
# the coverage map on the About screen opens. That check belongs with the rest
# of the on-hardware review of #31. If the map is the thing that fails, the
# first experiment is to uncomment the block below; if that fixes it, narrow it
# to the class named in the logcat stack trace and record the name here rather
# than leaving the wildcard in place.
#
#   -keep class org.maplibre.android.** { *; }
#   -keep class org.maplibre.maplibregl.** { *; }
