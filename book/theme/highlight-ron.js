(function() {
  "use strict";

  if (typeof hljs === "undefined") return;

  hljs.registerLanguage("ron", function(hljs) {
    return {
      name: "RON",
      aliases: ["ron"],
      contains: [
        hljs.C_LINE_COMMENT_MODE,
        hljs.C_BLOCK_COMMENT_MODE,
        {
          className: "string",
          begin: '"',
          end: '"',
          contains: [hljs.BACKSLASH_ESCAPE],
          illegal: "\\n"
        },
        {
          className: "number",
          begin: "\\b\\d+(\\.\\d+)?([eE][+-]?\\d+)?\\b",
          relevance: 0
        },
        {
          className: "literal",
          begin: "\\b(true|false)\\b"
        },
        {
          className: "attr",
          begin: "[a-zA-Z_][a-zA-Z0-9_]*\\s*:",
          relevance: 0
        }
      ]
    };
  });

  document.querySelectorAll("pre code.language-ron").forEach(function(block) {
    hljs.highlightBlock(block);
  });
})();
