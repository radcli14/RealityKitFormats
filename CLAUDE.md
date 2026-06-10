# RealityKitFormats - https://github.com/radcli14/RealityKitFormats

This is a Swift package that compiles 3D file reading and writing support from three repositories:
- https://github.com/radcli14/ModelIO-to-RealityKit
- https://github.com/radcli14/DAE-to-RealityKit
- https://github.com/radcli14/GLTFKit2 (fork of the same repository by `warrenm`)

I have local clones of the above in this folder, however, to propagate the changes into the live version of `RealityKitFormats`, I first need to tag and push to remotes of the above.

## Priorities

Fundamentally, this package must be tested and able to:
- Load from a 3D model file, URL, or Data object, and generate a RealityKit entity
- Export to a new 3D model file in an alternate format
- Reload the exported file, and generate a RealityKit entity that matches the appearance of the original, to the extent that there is feature parity between formats

Syntax should stay mostly the same between different formats, as the purpose of this package is to wrap the others into a unified developer experience.

`RealityKitFormats` is created as a support package for `AR Mobile Robotics` (`ARMOR`), which is an iOS app that generates RealityKit scenes from `URDF` and `MJCF` formatted robot descriptions.
Because these are legacy `XML` formats that reference 3D files, the app needs to support older 3D formats, specifically `DAE`, `STL`, and `OBJ`, that are standardized in `URDF` and `MJCF`, even if though they don't see wide use in modern web or AR applications.
`GLB` and `USDZ` should be supported because the *are* modern formats, common in web and AR, but are not common in robotics.
Apple's ModelIO supports a few other formats, but they aren't important to the `ARMOR` app.

## RealityKitFormatsViewer

This is a Mini UI-test app intended to visually verify imports and conversions by a human user.
The navigation bar includes a button to select a 3D model file, and a second button to select the display format.
The loaded entity is displayed in the center of the screen.
