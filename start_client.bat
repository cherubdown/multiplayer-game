@echo off
rem Imports the project first (fast when nothing changed), so the character
rem models load even on a checkout that was never opened in the editor.
if not exist .godot mkdir .godot
if not exist .godot\extension_list.cfg echo res://addons/godot-sqlite/gdsqlite.gdextension> .godot\extension_list.cfg
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
Godot_v4.7.2-stable_win64.exe --path . --join=127.0.0.1 %*
