module Api
  IOS = 'ios'.freeze # Xamarin.iOS projects
  MAC = 'mac'.freeze # Xamarin.Mac projects
  TVOS = 'tvos'.freeze # Xamarin.TVOS projects
  ANDROID = 'android'.freeze # Xamarin.Android projects
end

module Tests
  UITEST = 'uitest'.freeze # Xamarin.UITest projects - nunit.framework in combination with Xamarin.UITest.dll
  NUNIT = 'nunit'.freeze # .NET projects with referenced nunit.framework and with no Xamarin.UITest reference
  NUNIT_LITE = 'nunit_lite'.freeze # MonoTouch.NUnitLite project
end
