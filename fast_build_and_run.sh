#!/bin/bash
set -e

echo "Setting up build directory..."
# Remove existing build directory if it exists to ensure a clean state
rm -rf build
meson setup build

echo "Compiling Baobab..."
meson compile -C build

echo "Compiling GSettings schemas..."
glib-compile-schemas data/

echo "Launching Baobab..."
# We set GSETTINGS_SCHEMA_DIR so the app can find its settings without a full system install
export GSETTINGS_SCHEMA_DIR=$PWD/data
./build/src/baobab