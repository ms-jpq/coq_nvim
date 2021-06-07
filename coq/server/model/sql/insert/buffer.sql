INSERT INTO buffers (buffer,  tick)
VALUES              (:buffer, :tick)
ON CONFLICT (buffer)
DO UPDATE SET tick = :tick
