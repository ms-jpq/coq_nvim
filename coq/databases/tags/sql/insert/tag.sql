REPLACE INTO tags (`path`,             line,  name,  word_start,          lname,        pattern,  kind,  typeref,  scope,  scopeKind,  `access`)
VALUES            (X_NORM_CASE(:path), :line, :name, X_WORD_START(:name), LOWER(:name), :pattern, :kind, :typeref, :scope, :scopeKind, :access)

