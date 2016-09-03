int_array_to_hex = (int_array) ->
  return int_array.map((int) ->
    hex = int.toString(16)
    if hex.length < 2 then hex = '0' + hex
    return hex
  ).join(':')

module.exports.int_array_to_hex = int_array_to_hex
