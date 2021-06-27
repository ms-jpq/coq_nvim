UPDATE lines
SET line_num = line_num + :shift
WHERE
  line_num >= :lo

