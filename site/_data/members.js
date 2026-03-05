const fs = require("fs");

/**
 * Parse CAN_POST_CSV into a map of email → {name, methods: [{type, url}]}.
 * Methods are ordered as they appear in the CSV (author's preferred order).
 * URL type is detected by domain: wa.me → whatsapp, signal.me → signal.
 */
module.exports = () => {
  const csvPath = process.env.CAN_POST_CSV;
  if (!csvPath || !fs.existsSync(csvPath)) return {};

  const members = {};
  const lines = fs.readFileSync(csvPath, "utf8").split("\n");

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    const cols = trimmed.split(",").map((c) => c.trim());
    const email = cols[0];
    const name = cols[1] || email;

    const methods = [];
    for (let i = 2; i < cols.length; i++) {
      const url = cols[i];
      if (!url) continue;

      if (url.includes("wa.me")) {
        methods.push({ type: "whatsapp", url });
      } else if (url.includes("signal.me")) {
        methods.push({ type: "signal", url });
      }
    }
    // Email is always available as the last fallback.
    methods.push({ type: "email", url: email });

    members[email] = { name, methods };
  }

  return members;
};
