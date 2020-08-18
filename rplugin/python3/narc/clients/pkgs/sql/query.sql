SELECT word, nword
FROM words
WHERE
    nword LIKE ?
    AND
    nword <> ?
