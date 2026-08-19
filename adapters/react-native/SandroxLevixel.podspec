require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'SandroxLevixel'
  s.version = package['version']
  s.summary = package['description']
  s.description = package['description']
  s.license = package['license']
  s.author = package['author']
  s.homepage = package['homepage']
  s.source = { git: package['repository']['url'], tag: s.version.to_s }
  s.platform = :ios, '15.1'
  s.swift_version = '5.9'
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  s.source_files = 'ios/*.swift'
  s.vendored_frameworks = 'ios/Frameworks/Levixel.xcframework'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }
end
