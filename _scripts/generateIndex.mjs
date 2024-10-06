import * as fs from 'node:fs';
import { remark } from 'remark'
import html from 'remark-html';

remark()
  .use(html)
  .process(fs.readFileSync('README.md'), (err, file) => {
    if (err) throw err;
    const content = String(file);
    console.log(`<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>README</title>
</head>
<body>
    ${content}</body>
</html>`);
  });
