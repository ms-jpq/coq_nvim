local merge
merge = function (ds1, ds2)
  if type(ds1) == "table" and type(ds2) == "table" then
    acc = {}
    for k, v in pairs(ds1) do
      acc[k] = v
    end
    for k, v in pairs(ds2) do
      acc[k] = merge(ds1[k], v)
    end
    return acc
  else
    return ds2
  end
end


return {
  merge = merge
}
