require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "vision-camera-ocr"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "13.0" }
  s.source       = { :git => "https://github.com/pcgversion/vision-camera-ocr.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"

  s.dependency "React-Core"
  s.dependency "GoogleMLKit/TextRecognition", "4.0.0"

  # Swift/Obj-C bridging
  s.pod_target_xcconfig = {

    # OpenCV headers path
    'FRAMEWORK_SEARCH_PATHS' => '$(PODS_ROOT)/opencv2.framework',

    # OpenCV headers path
    'HEADER_SEARCH_PATHS' => '$(PODS_ROOT)/opencv2.framework/Versions/A/Headers',
    
    # Swift module configuration
    'SWIFT_INCLUDE_PATHS' => '$(PODS_ROOT)/opencv2.framework/Versions/A/Headers',
  
  }
 
end
