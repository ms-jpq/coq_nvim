REPLACE INTO tags (`path`,             line,  name,  lname,        pattern,  kind,  typeref,  scope,  scopeKind,  `access`)
VALUES            (X_NORM_CASE(:path), :line, :name, LOWER(:name), :pattern, :kind, :typeref, :scope, :scopeKind, :access)

