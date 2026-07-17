Signing Rosette means two different entitlements for various reasons. You have an ad-hoc version of these entitlements, which is meant for if you are building the Rosette application yourself and the various installers. Ad-hoc versions are terrible for distribution, as it will be seen as malicious code by Gatekeeper. 

Here is the ad-hoc version and its code:
```rosette-adhoc.entitlements
<?xml version="1.0" encoding="UTF-8"?>

<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">

<plist version="1.0">

<dict>

<key>com.apple.security.cs.allow-jit</key>

<true/>

<key>com.apple.security.cs.allow-unsigned-executable-memory</key>

<true/>

<key>com.apple.security.cs.disable-library-validation</key>

<true/>

</dict>

</plist>
```

It is required you disable library validation because otherwise, Gatekeeper will complain. This is why it tends to be a pain in the ass to distribute anything signed from a non-Apple Developer Program account. And why it was my goto until I decided to shove $99 at the problem

The Release version of the entitlements only removes that library validation, as seen here:
```rosette-release.entitlements
<?xml version="1.0" encoding="UTF-8"?>

<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">

<plist version="1.0">

<dict>

<key>com.apple.security.cs.allow-jit</key>

<true/>

<key>com.apple.security.cs.allow-unsigned-executable-memory</key>

<true/>

</dict>

</plist>
```

In an upcoming version, I do want to remove the 'allow unsigned executable memory' key since this is NOT macOS compliant. For the App Store, an official release, having that in the entitlements would lead to an automatic rejection. If I were to ever do an iPhone port (unlikely in the near future), I'd also have to disable the allowance of JIT (and create a new entitlement file), as Apple refuses to allow any JIT code to run (and will reject any apps from the App Store that enable JIT, outside of rare contexts). In that instance, I'd need a custom JIT to AOT library that would interpret JIT into AOT compiled code. 