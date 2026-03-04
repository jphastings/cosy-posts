module.exports = function (eleventyConfig) {
  eleventyConfig.addPassthroughCopy("content/**/*.{jpg,jpeg,png,gif,mp4,mov,webm,m4a,mp3}");
  eleventyConfig.addPassthroughCopy("css");

  eleventyConfig.addFilter("readableDate", (dateStr) => {
    const d = new Date(dateStr);
    return d.toLocaleDateString("en-GB", {
      day: "numeric",
      month: "short",
      year: "numeric",
    });
  });

  eleventyConfig.addFilter("isoDate", (dateStr) => {
    return new Date(dateStr).toISOString();
  });

  // Render markdown body text to HTML.
  const md = require("markdown-it")({ html: true, linkify: true });
  eleventyConfig.addFilter("renderMarkdown", (text) => {
    if (!text) return "";
    return md.render(text);
  });

  eleventyConfig.setServerOptions({ port: 8888 });

  return {
    dir: { input: ".", output: "_site", includes: "_includes", data: "_data" },
  };
};
