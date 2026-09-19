// Express middleware factory: validates req.body against a Zod schema,
// replaces req.body with the parsed (defaulted/coerced) result, or responds
// 400 with the validation issues.
function validateBody(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      return res.status(400).json({ error: "invalid request body", issues: result.error.issues });
    }
    req.body = result.data;
    next();
  };
}

// Same idea for query strings. Express 5 makes req.query a read-only getter,
// so the parsed result goes on res.locals.query instead of replacing it.
function validateQuery(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.query);
    if (!result.success) {
      return res.status(400).json({ error: "invalid query parameters", issues: result.error.issues });
    }
    res.locals.query = result.data;
    next();
  };
}

module.exports = { validateBody, validateQuery };
