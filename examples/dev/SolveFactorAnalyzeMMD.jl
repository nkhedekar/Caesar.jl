

fctsym # bearingrange

asMeas, asPred = solveFactorMeasurements(dfg, fctsym)


mmd!

cr = manikde!(asPred[1:1,:], Sphere1)
cr0 = manikde!(asMeas[1:1,:], Sphere1)
plotKDECircular([cr;cr0], c=["blue";"magenta"])

cr = manikde!(asPred[2:2,:], ContinuousScalar)
cr0 = manikde!(asMeas[2:2,:], ContinuousScalar)
plotKDE([cr;cr0], c=["blue";"magenta"])

val = Float64[0.0;]

me1 = deepcopy(asPred[2,:])

function makemeas!(i, me1, dm)
  me1[i] = dm
  return me1
end

mmd!(val, asMeas[2,:], me1)

pg = (i, dx) -> mmd!(val, asMeas[2,:], makemeas!(i, me1, dx))


pgi = (dx) -> pg(10,dx)
# pgi(-10.0)
# pgi(0.0)
# pgi(10.0)

XX = -50:0.1:300
Gadfly.plot(x=XX, y=pgi.(XX), Geom.line)
