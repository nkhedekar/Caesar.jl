"""
    Proof of concept for Caesar-ROS integration
    (check Caesar Docs for details)
    https://juliarobotics.org/Caesar.jl/latest/examples/using_ros/

    Prerequisites:
    - source /opt/ros/noetic/setup.bash
    - cd ~/thecatkin_ws
        - source devel/setup.bash in all 3 terminals
    - run roscore in one terminal
    - Then run this Julia in another terminal/process.

    Input:
    - Make sure the rosbag is in ~/data/Marine/philos_car_far.bag

    Output:
    - Generates output dfg tar and data folder at /tmp/caesar/philos 
        containing data from the bagfile, see below for details.

    Future:
    - ROS msg replies
    - periodic export of factor graph object
"""

## Prepare python version
using Distributed
# addprocs(4)

using Pkg
Distributed.@everywhere using Pkg

Distributed.@everywhere begin
  ENV["PYTHON"] = "/usr/bin/python3"
  Pkg.build("PyCall")
end

using PyCall
Distributed.@everywhere using PyCall

## INIT
using RobotOS

# Also rosnode info
# standard types
@rosimport sensor_msgs.msg: PointCloud2
@rosimport sensor_msgs.msg: NavSatFix
@rosimport sensor_msgs.msg: CompressedImage
# @rosimport nmea_msgs.msg: Sentence
# seagrant type

# Application specific ROS message types from catkin workspace
# @rosimport seagrant_msgs.msg: radar

rostypegen()

## Load Caesar with additional tools

using Colors
using Caesar
# using Caesar._ROS

##

# using RoME
# using DistributedFactorGraphs

using DistributedFactorGraphs.DocStringExtensions
using Dates
using JSON2
using BSON
using Serialization
using FixedPointNumbers
using StaticArrays
using ImageMagick, FileIO
using Images

using ImageDraw

##

# /gps/fix              10255 msgs    : sensor_msgs/NavSatFix
# /gps/nmea_sentence    51275 msgs    : nmea_msgs/Sentence
# /radar_pointcloud_0    9104 msgs    : sensor_msgs/PointCloud2
# /velodyne_points      20518 msgs    : sensor_msgs/PointCloud2

# function handleGPS(msg, fg)
# end


"""
    $TYPEDEF
Quick placeholder for the system state - we're going to use timestamps to align all the data.
"""
Base.@kwdef mutable struct SystemState
    curtimestamp::Float64 = -1000
    cur_variable::Union{Nothing, DFGVariable} = nothing
    var_index::Int = 0
    lidar_scan_index::Int = 0
    max_lidar::Int = 3
    radar_scan_queue::Channel{sensor_msgs.msg.PointCloud2} = Channel{sensor_msgs.msg.PointCloud2}(64)
    # SystemState() = new(-1000, nothing, 0, 0, 3)
end

##

"""
    $(SIGNATURES)
Update the system state variable if the timestamp has changed (increment variable)
"""
function updateVariableIfNeeded(fg::AbstractDFG, systemstate::SystemState, newtimestamp::Float64)
    # Make a new variable if so.
    if systemstate.curtimestamp == -1000 || systemstate.cur_variable === nothing || systemstate.curtimestamp < newtimestamp
        systemstate.curtimestamp = newtimestamp
        systemstate.cur_variable = addVariable!(fg, Symbol("x$(systemstate.var_index)"), Pose2, timestamp = unix2datetime(newtimestamp))
        systemstate.var_index += 1
        systemstate.lidar_scan_index = 0
    end
    return nothing
end



"""
    $SIGNATURES

Message callback for Radar pings. Adds a variable to the factor graph and appends the scan as a bigdata element.
"""
function handleRadarPointcloud!(msg::sensor_msgs.msg.PointCloud2, fg::AbstractDFG, systemstate::SystemState)
    @info "handleRadarPointcloud!" maxlog=10

    # assume there is still space (previously cleared)
    # add new piece of radar point cloud to queue for later processing.
    put!(systemstate.radar_scan_queue, msg)

    # check if the queue still has space
    if length(systemstate.radar_scan_queue.data) < systemstate.radar_scan_queue.sz_max
        # nothing more to do
        return nothing
    end
    
    # Full sweep, lets empty the queue and add a variable
    # type instability
    queueScans = Vector{Any}(undef, systemstate.radar_scan_queue.sz_max)

    # get the first
    md = take!(systemstate.radar_scan_queue)
    pc2 = Caesar._PCL.PCLPointCloud2(md)
    pc_cat = Caesar._PCL.PointCloud(pc2)
    
    queueScans[1] = pc2

    for i in 1:length(systemstate.radar_scan_queue.data)
        # something minimal, will do util for transforming PointCloud2 next
        md = take!(systemstate.radar_scan_queue)
        # @info typeof(md) fieldnames(typeof(md))
        pc2 = Caesar._PCL.PCLPointCloud2(md)
        pc_ = Caesar._PCL.PointCloud(pc2)
        pc_cat = cat(pc_cat, pc_; reuse=true)

        queueScans[i] = (pc2) 
    end

    # add a new variable to the graph
    timestamp = Float64(msg.header.stamp.secs) + Float64(msg.header.stamp.nsecs)/1.0e9
    systemstate.curtimestamp = timestamp
    systemstate.cur_variable = addVariable!(fg, Symbol("x$(systemstate.var_index)"), Pose2, timestamp = unix2datetime(timestamp), tags=[:POSE])
    systemstate.var_index += 1

    io = IOBuffer()
    serialize(io, queueScans)

    # @show datablob = pc # queueScans
    # and add a data blob of all the scans
    # Make a data entry in the graph
    addData!(   fg, :radar, systemstate.cur_variable.label, :RADAR_PC2s, 
                take!(io), # get base64 binary
                # Vector{UInt8}(JSON2.write(datablob)),  
                mimeType="application/octet-stream/julia.serialize",
                description="queueScans = Serialization.deserialize(PipeBuffer(readBytes))")
    #

    io = IOBuffer()
    serialize(io, pc_cat)

    addData!(   fg, :radar, systemstate.cur_variable.label, :RADAR_SWEEP,
                take!(io),
                mimeType="application/octet-stream/julia.serialize",
                description="queueScans = Serialization.deserialize(PipeBuffer(readBytes))" )
    #

    # also make and add an image of the radar sweep
    img = makeImage!(pc_cat)
    addData!(   fg, :radar, systemstate.cur_variable.label, :RADAR_IMG,
                Caesar.toFormat(format"PNG", img),
                mimeType="image/png",
                description="ImageMagick.readblob(imgBytes)" )
    #

    nothing
end

"""
    $SIGNATURES

Message callback for LIDAR point clouds. Adds a variable to the factor graph and appends the scan as a bigdata element.
Note that we're just appending all the LIDAR scans to the variables because we are keying by RADAR.
"""
function handleLidar!(msg::sensor_msgs.msg.PointCloud2, fg::AbstractDFG, systemstate::SystemState)
    @info "handleLidar" maxlog=10
    # Compare systemstate and add the LIDAR scans if we want to.
    if systemstate.cur_variable === nothing
        return nothing
    end
    timestamp = Float64(msg.header.stamp.secs) + Float64(msg.header.stamp.nsecs)/1.0e9
    @info "[$timestamp] LIDAR pointcloud sample on $(systemstate.cur_variable.label) (sample $(systemstate.lidar_scan_index+1))"

    # Check if we have enough LIDAR's for this variable
    if systemstate.lidar_scan_index >= systemstate.max_lidar
        @warn "Ditching LIDAR sample for this variable, already have enough..."
        return nothing
    end

    # Make a data entry in the graph
    ade,adb = addData!(fg, :lidar, systemstate.cur_variable.label, Symbol("LIDAR$(systemstate.lidar_scan_index)"), Vector{UInt8}(JSON2.write(msg)), mimeType="/velodyne_points;dataformat=Float32*[[X,Y,Z]]*32")

    # NOTE: If JSON, then do this to get to Vector{UInt8} - # byteData = Vector{UInt8}(JSON2.write(xyzLidarF32))

    # Increment LIDAR scan count for this timestamp
    systemstate.lidar_scan_index += 1
end

"""
    $SIGNATURES

Message callback for Radar pings. Adds a variable to the factor graph and appends the scan as a bigdata element.
"""
function handleGPS!(msg::sensor_msgs.msg.NavSatFix, fg::AbstractDFG, systemstate::SystemState)
    @info "handleGPS" maxlog=10
    if systemstate.cur_variable === nothing
        # Keyed by the radar, skip if we don't have a variable yet.
        return nothing
    end
    timestamp = Float64(msg.header.stamp.secs) + Float64(msg.header.stamp.nsecs)/10^9
    # Update the variable if needed
    # updateVariableIfNeeded(fg, systemstate, timestamp)
    @info "[$timestamp] GPS sample on $(systemstate.cur_variable.label)"
    
    if :GPS in listDataEntries(fg, systemstate.cur_variable.label)
        @warn "GPS sample on $(systemstate.cur_variable.label) already exist, dropping"
        return nothing 
    end

    io = IOBuffer()
    JSON2.write(io, msg)
    ade,adb = addData!(fg, :gps_fix, systemstate.cur_variable.label, :GPS, take!(io),  mimeType="application/json", description="JSON2.read(IOBuffer(datablob))")

end


"""
    $SIGNATURES

Message callback for camera images.
"""
function handleCamera_Center!(msg::sensor_msgs.msg.CompressedImage, fg::AbstractDFG, systemstate::SystemState)
  @info "handleCamera_Center!" maxlog=10

  lbls = ls(fg, tags=[:POSE;])
  if length(lbls) == 0
    return nothing
  end

  lb = sortDFG(lbls)[end]

  addData!(   fg, :camera, systemstate.cur_variable.label, Symbol(:IMG_CENTER_, msg.header.seq),
              msg.data,
              mimeType="image/jpeg",
              description="ImageMagick.readblob(imgBytes); # "*msg.format*"; "*string(msg.header.stamp) )

  nothing
end


##

function main(;iters::Integer=50)
    dfg_datafolder = "/tmp/caesar/philos"
    if isdir(dfg_datafolder)
        println("Deleting old contents at: ",dfg_datafolder)
        rm(dfg_datafolder; force=true, recursive=true)
    end
    mkdir(dfg_datafolder)

    @info "Hit CTRL+C to exit and save the graph..."

    init_node("asv_feed")
    # find the bagfile
    bagfile = joinpath(ENV["HOME"],"data","Marine","philos_car_far.bag")
    bagSubscriber = RosbagSubscriber(bagfile)

    # Initialization
    fg = initfg()
    getSolverParams(fg).inflateCycles=1

    ds = FolderStore{Vector{UInt8}}(:radar, "$dfg_datafolder/data/radar")
    addBlobStore!(fg, ds)

    ds = FolderStore{Vector{UInt8}}(:gps_fix, "$dfg_datafolder/data/gps")
    addBlobStore!(fg, ds)

    # add if you want lidar also 
    ds = FolderStore{Vector{UInt8}}(:lidar, "$dfg_datafolder/data/lidar")
    addBlobStore!(fg, ds)

    # add if you want lidar also 
    ds = FolderStore{Vector{UInt8}}(:camera, "$dfg_datafolder/data/camera")
    addBlobStore!(fg, ds)


    # System state
    systemstate = SystemState()

    # Enable and disable as needed.
    camcen_sub = bagSubscriber("/center_camera/image_color/compressed", sensor_msgs.msg.CompressedImage, handleCamera_Center!, (fg, systemstate) )
    radarpc_sub = bagSubscriber("/broadband_radar/channel_0/pointcloud", sensor_msgs.msg.PointCloud2, handleRadarPointcloud!, (fg, systemstate) )
    # Skipping LIDAR
    # lidar_sub = Subscriber{sensor_msgs.msg.PointCloud2}("/velodyne_points", sensor_msgs.msg.PointCloud2, handleLidar!, (fg,systemstate), queue_size = 10)
    gps_sub = bagSubscriber("/gnss", sensor_msgs.msg.NavSatFix, handleGPS!, (fg, systemstate))


    @info "subscribers have been set up; entering main loop"
    # loop_rate = Rate(20.0)
    while loop!(bagSubscriber)
        iters -= 1
        iters < 0 ? break : nothing
    end

    @info "Exiting"
    # After the graph is built, for now we'll save it to drive to share.
    # Save the DFG graph with the following:
    @info "Saving DFG to $dfg_datafolder/dfg"
    saveDFG(fg, "$dfg_datafolder/dfg")

end

##


# Actually run the program and build 
main(iters=100000)



## ===========================================================================================
## after the graph is saved it can be loaded and the datastores retrieved

dfg_datafolder = "/tmp/caesar/philos"

fg = loadDFG("$dfg_datafolder/dfg")

ds = FolderStore{Vector{UInt8}}(:radar, "$dfg_datafolder/data/radar")
addBlobStore!(fg, ds)

ds = FolderStore{Vector{UInt8}}(:gps_fix, "$dfg_datafolder/data/gps")
addBlobStore!(fg, ds)

# add if you want lidar also 
ds = FolderStore{Vector{UInt8}}(:lidar, "$dfg_datafolder/data/lidar")
addBlobStore!(fg, ds)

# add if you want lidar also 
ds = FolderStore{Vector{UInt8}}(:camera, "$dfg_datafolder/data/camera")
addBlobStore!(fg, ds)

##