INSERT INTO tags (             filename,   line_num,             context,               kind,               name)
VALUES           (X_NORMALIZE(:filename), :line_num, X_NORMALIZE(context), X_NORMALIZE(:kind), X_NORMALIZE(:name))

