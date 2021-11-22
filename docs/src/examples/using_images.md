# Images and AprilTags

One common use in SLAM is [AprilTags.jl](https://github.com/JuliaRobotics/AprilTags.jl).  Please see that repo for documentation on detecting tags in images.  Note that Caesar.jl has a few built in tools for working with [Images.jl](https://github.com/JuliaImages/Images.jl) too.

```julia
using AprilTags
using Images, Caesar
```

Which immediately enables a new factor specifically developed for using AprilTags in a factor graph:
```@docs
Caesar.Pose2AprilTag4Corners
```

!!! note
    More details to follow.