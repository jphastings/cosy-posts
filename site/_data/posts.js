const fs = require("fs");
const path = require("path");
const matter = require("gray-matter");

const MEDIA_EXTS = new Set([
  ".jpg", ".jpeg", ".png", ".gif", ".webp",
  ".mp4", ".mov", ".webm",
  ".m4a", ".mp3",
]);

const VIDEO_EXTS = new Set([".mp4", ".mov", ".webm"]);

function findPosts(dir) {
  const posts = [];
  if (!fs.existsSync(dir)) return posts;

  const walk = (d) => {
    for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        walk(path.join(d, entry.name));
      } else if (entry.name === "index.md" || entry.name === "index.djot") {
        const filePath = path.join(d, entry.name);
        const raw = fs.readFileSync(filePath, "utf8");
        const { data: frontmatter, content: body } = matter(raw);

        // Find sibling media files.
        const siblings = fs.readdirSync(d);
        const media = siblings
          .filter((f) => MEDIA_EXTS.has(path.extname(f).toLowerCase()))
          .sort()
          .map((f) => {
            const ext = path.extname(f).toLowerCase();
            return {
              filename: f,
              path: "/" + path.relative(path.join(__dirname, ".."), path.join(d, f)),
              isVideo: VIDEO_EXTS.has(ext),
            };
          });

        // Post URL path (relative to content/).
        const relDir = path.relative(path.join(__dirname, "..", "content"), d);

        posts.push({
          date: frontmatter.date || "",
          location: frontmatter.location || null,
          tags: frontmatter.tags || [],
          body: body.trim(),
          media,
          url: "/content/" + relDir + "/",
          id: path.basename(d),
        });
      }
    }
  };

  walk(dir);

  // Sort by date descending.
  posts.sort((a, b) => new Date(b.date) - new Date(a.date));
  return posts;
}

module.exports = () => findPosts(path.join(__dirname, "..", "content"));
