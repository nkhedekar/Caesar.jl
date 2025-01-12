
# julia -O3 -p12 LCM_SLAM_client.jl -i 20000

# JULIA_NUM_THREADS=10 julia -O3 -p10 LCM_SLAM_client.jl -i 200000 -s 0.1 --kappa_odo 20.0 --magStdDeg 5.0 --stride_range 3 --odoGyroBias --dbg --savePlotting --fixedlag 100 --genResults
# JULIA_NUM_THREADS=4 julia -O3 -p10 LCM_SLAM_client.jl -i 350000 -s 0.1 --kappa_odo 30.0 --magStdDeg 3.0 --stride_range 3 --odoGyroBias --dbg --savePlotting --fixedlag 50


# JULIA_NUM_THREADS=9 julia -O3 GenerateResults.jl --reportDir /tmp/caesar/2020-02-19T12\:50\:59.092/fg_after_x71.tar.gz --plotSeriesBeliefs 0 --skip
# JULIA_NUM_THREADS=9 julia -O3 GenerateResults.jl --reportDir /tmp/caesar/2020-02-23T01\:43\:32.222/fg_after_x1391.tar.gz --plotSeriesBeliefs 0 --skip
# JULIA_NUM_THREADS=9 julia -O3 GenerateResults.jl --reportDir /tmp/caesar/2020-02-23T16\:02\:36.776/fg_after_x471.tar.gz --plotSeriesBeliefs 0 --skip
# JULIA_NUM_THREADS=9 julia -O3 GenerateResults.jl --reportDir /tmp/caesar/2020-02-23T03\:28\:10.097/fg_after_x1391.tar.gz --plotSeriesBeliefs 0 --skip



#
# ffmpeg -start_number 21 -i /tmp/caesar/2020-01-27T01\:46\:52.871/lines/fg_x%d.png -c:v libx264 -r 30 -pix_fmt yuv420p ~/Videos/out871.mp4
# ffmpeg -start_number 21 -i /tmp/caesar/2020-01-29T01\:13\:04.735/lines/fg_x%d.png -c:v h264_nvenc -r 30 -pix_fmt yuv420p ~/Videos/out735.mp4


# export DISPLAY=':99.0'
# Xvfb :99 -screen 0 1024x768x24 > /dev/null 2>&1 &
# JULIA_NUM_THREADS=4 julia131 -O3 -p10 LCM_SLAM_client.jl -i 350000 -s 0.1 --kappa_odo 5.0 --magStdDeg 3.0 --stride_range 3 --odoGyroBias --dbg --savePlotting --fixedlag 50
