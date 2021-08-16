REPLACE INTO tags (`path`, line,  name, lname,         pattern,  kind,  typeref,  scope,  scopeKind, `access`)
VALUES            (:path, :line, :name, LOWER(:name), :pattern, :kind, :typeref, :scope, :scopeKind, :access)

