INSERT OR IGNORE INTO
  words (
    buffer_id,
    word,
    lword,
    lo,
    hi,
    kind,
    pword,
    pkind,
    gpword,
    gpkind
  )
VALUES
  (
    :buffer_id,
    :word,
    LOWER(:word),
    :lo,
    :hi,
    :kind,
    :pword,
    :pkind,
    :gpword,
    :gpkind
  )
