Pod::Spec.new do |s|
  s.name = 'sandrox_levixel'
  s.version = '1.5.0'
  s.summary = 'Native image and video viewing with shared thumbnail transitions.'
  s.homepage = 'https://github.com/sandroxy/levixel'
  s.license = { :type => 'MIT', :file => '../LICENSE' }
  s.author = 'SandroX'
  s.source = { :git => 'https://github.com/sandroxy/levixel.git', :tag => s.version.to_s }
  s.source_files = 'sandrox_levixel/Sources/sandrox_levixel/**/*.swift'
  s.vendored_frameworks = 'sandrox_levixel/Frameworks/Levixel.xcframework'
  s.dependency 'Flutter'
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
