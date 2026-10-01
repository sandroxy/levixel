#!/usr/bin/env ruby
# frozen_string_literal: true

gem 'xcodeproj', '= 1.27.0'
require 'xcodeproj'

project_path = File.expand_path(ARGV.fetch(0))
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |target| target.name == 'Runner' }
abort 'The Flutter source host is missing its Runner target' unless app
target = project.targets.find { |entry| entry.name == 'RunnerUITests' }
unless target
  target = project.new_target(:ui_test_bundle, 'RunnerUITests', :ios, '15.0', nil, :swift)
  target.add_dependency(app)
end
target.build_configurations.each do |configuration|
  configuration.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.sandrox.tests.levixelSourceHost.uitests',
    'SWIFT_VERSION' => '5.0',
    'TEST_TARGET_NAME' => 'Runner',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'CODE_SIGNING_ALLOWED' => 'NO',
    'TARGETED_DEVICE_FAMILY' => '1,2'
  )
end
group = project.main_group.find_subpath('RunnerUITests', true)
group.set_source_tree('<group>')
group.set_path('RunnerUITests')
file = group.files.find { |entry| entry.path == 'RunnerUITests.swift' } || group.new_file('RunnerUITests.swift')
target.source_build_phase.add_file_reference(file, true)
project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][target.uuid] = {
  'CreatedOnToolsVersion' => '26.3', 'TestTargetID' => app.uuid
}
project.save

# Preserve Flutter's generated build preparation actions, including SwiftPM.
scheme = Xcodeproj::XCScheme.new(File.join(project_path, 'xcshareddata/xcschemes/Runner.xcscheme'))
testables = scheme.test_action.xml_element.elements['Testables']
testables.elements.to_a.each { |entry| testables.delete_element(entry) }
scheme.add_build_target(target, false)
scheme.add_test_target(target)
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(project_path, 'NativeGestures', true)
