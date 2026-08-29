#!/usr/bin/env ruby
# frozen_string_literal: true

# One-time setup script: adds the "Share Extension" app-extension target
# (spec A6 — OS share-sheet integration) to Runner.xcodeproj.
#
# Safe to re-run: it's a no-op if the target already exists.
#
# Usage:
#   cd ios && ruby add_share_extension.rb

require 'xcodeproj'

PROJECT_PATH = 'Runner.xcodeproj'
TARGET_NAME = 'Share Extension'
BUNDLE_ID = 'com.teedup.golf.ShareExtension'
APP_GROUP = 'group.com.teedup.golf.share'
DEPLOYMENT_TARGET = '16.0'

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "Target '#{TARGET_NAME}' already exists — nothing to do."
  exit 0
end

runner_target = project.targets.find { |t| t.name == 'Runner' }
raise "Could not find 'Runner' target" unless runner_target

runner_team = runner_target.build_configuration_list.build_configurations
                           .map { |c| c.build_settings['DEVELOPMENT_TEAM'] }
                           .compact.first

# ---------------------------------------------------------------------------
# 1. Group + file references
# ---------------------------------------------------------------------------

group = project.main_group.new_group(TARGET_NAME, TARGET_NAME)
# NOTE: paths here are relative to the group's own path ("Share Extension/"),
# set above — do not repeat the folder name.
info_plist_ref = group.new_reference('Info.plist')
swift_ref = group.new_reference('ShareViewController.swift')
entitlements_ref = group.new_reference("#{TARGET_NAME}.entitlements")
storyboard_ref = group.new_reference('Base.lproj/MainInterface.storyboard')

# ---------------------------------------------------------------------------
# 2. Native target
# ---------------------------------------------------------------------------

extension_target = project.new_target(
  :app_extension,
  TARGET_NAME,
  :ios,
  DEPLOYMENT_TARGET,
  nil,
  :swift
)

extension_target.add_file_references([swift_ref])
extension_target.resources_build_phase.add_file_reference(storyboard_ref)

extension_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  config.build_settings['PRODUCT_NAME'] = TARGET_NAME
  config.build_settings['INFOPLIST_FILE'] = "#{TARGET_NAME}/Info.plist"
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "#{TARGET_NAME}/#{TARGET_NAME}.entitlements"
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = runner_team if runner_team
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  config.build_settings['CUSTOM_GROUP_ID'] = APP_GROUP
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] =
    '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
end

# Give Runner the same CUSTOM_GROUP_ID + entitlements file so its own
# targets/scripts can reference the same app group.
runner_target.build_configurations.each do |config|
  config.build_settings['CUSTOM_GROUP_ID'] = APP_GROUP
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# ---------------------------------------------------------------------------
# 3. Embed the extension into Runner + dependency
# ---------------------------------------------------------------------------

runner_target.add_dependency(extension_target)

embed_phase = runner_target.new_copy_files_build_phase('Embed Foundation Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_phase.add_file_reference(extension_target.product_reference, true)

# Flutter injects a "Thin Binary" run-script phase; the plugin's docs warn
# the embed phase must run BEFORE it, or the extension's module can't be
# found in the compiled app. Move Embed Foundation Extensions to just
# before that script phase (or to the very end if it isn't found yet —
# `flutter pub get`/first build will still create it after this target
# exists, so it may not be present on repeated runs of this script).
phases = runner_target.build_phases
thin_binary_index = phases.find_index do |p|
  p.respond_to?(:name) && p.name == 'Thin Binary'
end
if thin_binary_index
  phases.delete(embed_phase)
  phases.insert(thin_binary_index, embed_phase)
end

project.save

puts "Added target '#{TARGET_NAME}' (#{BUNDLE_ID}) to #{PROJECT_PATH}."
puts 'Next: run `pod install` in ios/, then build.'
