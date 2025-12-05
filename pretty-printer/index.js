// # Pretty Printer
//
// This is an implementation of a pretty printer library.
//
// It comes from [Pretty Fast Pretty Printer][] ([ed78c97][]) by brownplt:
//
// Pretty printing is an approach to printing source code that can adapt how things are printed to fit within a maximum line width.
//
// There are a variety of pretty-printing algorithms. The
// pretty-fast-pretty-printer uses a custom algorithm
// that displays a document in time **linear** in the number of distinct nodes in
// the document. (Note that this is better than linear in the _size_ of the
// document: if a document contains multiple references to a single sub-document,
// that sub-document is only counted _once_. This can be an exponential
// improvement.)
//
// The algorithm takes inspiration from:
//
// 1. Wadler's
// [Prettier Printer][],
// 2. Bernardy's
// [Pretty but not Greedy Printer][], and
// 3. Ben Lerner's
// [Pyret pretty printer][]
//
// This pretty printer was developed as part of [Codemirror Blocks][]
//
// Don't let this stop you from using it for your own project, though: it's a
// general purpose library!
//
// [Pretty Fast Pretty Printer]: https://github.com/brownplt/pretty-fast-pretty-printer
// [ed78c97]: https://github.com/brownplt/pretty-fast-pretty-printer/blob/4f35205ddd5cbe3ff699f53364693026a1ffdbbc/index.js
// [Prettier Printer]: http://homepages.inf.ed.ac.uk/wadler/papers/prettier/prettier.pdf
// [Pretty but not Greedy Printer]: https://jyp.github.io/pdf/Prettiest.pdf
// [Pyret pretty printer]: https://github.com/brownplt/pyret-lang/blob/horizon/src/arr/trove/pprint.arr
// [Codemirror Blocks]: https://github.com/bootstrapworld/codemirror-blocks
//
// **License:** [MIT](https://github.com/brownplt/pretty-fast-pretty-printer/blob/4f35205ddd5cbe3ff699f53364693026a1ffdbbc/LICENSE)<br>
// **Copyright:** © 2019 Brown University PLT

function txt(arg) {
  let text = arg.toString(); // coerce to a string if it isn't already
  if (text.indexOf("\n") !== -1) {
    throw (
      "pretty.js: The `txt` function does not accept text with newlines, but was given: " +
      text
    );
  }
  return new TextDoc(text);
}
function horz() {
  return horzArray(Array.from(arguments));
}
function vert() {
  return vertArray(Array.from(arguments));
}
function concat() {
  return concatArray(Array.from(arguments));
}
function horzArray(array) {
  if (array.length == 0) return txt("");
  let docArray = array.map((item) => coerce(item));
  return docArray.reduce((result, doc) => new HorzDoc(result, doc));
}
function vertArray(array) {
  if (array.length == 0) return txt("");
  let docArray = array.map((item) => coerce(item));
  return docArray.reduce((result, doc) => new VertDoc(result, doc));
}
function concatArray(array) {
  let docArray = array.map((item) => coerce(item));
  return docArray.reduce((result, doc) => new ConcatDoc(result, doc));
}
function ifFlat(flat, broken) {
  return new IfFlatDoc(coerce(flat), coerce(broken));
}
function fullLine(doc) {
  return new FullLineDoc(coerce(doc));
}

/******************************************************************************
 * Documents
 *
 *   display(width):
 *     "Pretty print a document within the given width. Returns a list of lines."
 *
 *   render(out, indent, column, width):
 *     "Render the document. This is the recursive call of display()."
 *     out:    The list of lines to print to.
 *     indent: The column to return to in case of a line break.
 *     column: The current column.
 *     width:  The max width that the pretty printing is allowed to be.
 *     -> returns the current column after printing
 *
 ******************************************************************************/

class Doc {
  constructor(flat_width) {
    this.flat_width = flat_width;
  }

  display(width) {
    let outputLines = [""];
    this.render(outputLines, 0, 0, width);
    return outputLines;
  }
}

class TextDoc extends Doc {
  constructor(text) {
    super(text.length);
    this.text = text;
  }

  render(out, indent, column, width) {
    out[out.length - 1] += this.text; // print the text to the last line
    return column + this.text.length;
  }
}

class HorzDoc extends Doc {
  constructor(doc1, doc2) {
    if (doc1.flat_width === null || doc2.flat_width === null) {
      super(null);
    } else {
      super(doc1.flat_width + doc2.flat_width);
    }
    this.doc1 = doc1;
    this.doc2 = doc2;
  }

  render(out, indent, column, width) {
    let newColumn = this.doc1.render(out, indent, column, width);
    return this.doc2.render(out, newColumn, newColumn, width);
  }
}

class ConcatDoc extends Doc {
  constructor(doc1, doc2) {
    if (doc1.flat_width === null || doc2.flat_width === null) {
      super(null);
    } else {
      super(doc1.flat_width + doc2.flat_width);
    }
    this.doc1 = doc1;
    this.doc2 = doc2;
  }

  render(out, indent, column, width) {
    let newColumn = this.doc1.render(out, indent, column, width);
    return this.doc2.render(out, indent, newColumn, width);
  }
}

class VertDoc extends Doc {
  constructor(doc1, doc2) {
    super(null);
    this.doc1 = doc1;
    this.doc2 = doc2;
  }

  render(out, indent, column, width) {
    this.doc1.render(out, indent, column, width);
    out.push(new Array(indent + 1).join(" ")); // print newline and indent
    return this.doc2.render(out, indent, indent, width);
  }
}

class FullLineDoc extends Doc {
  constructor(doc) {
    super(null);
    this.doc = doc;
  }

  render(out, indent, column, width) {
    return this.doc.render(out, indent, column, width);
  }
}

class IfFlatDoc extends Doc {
  constructor(flat, broken) {
    if (flat.flat_width === null) {
      super(broken.flat_width);
    } else if (broken.flat_width === null) {
      super(flat.flat_width);
    } else {
      super(Math.min(flat.flat_width, broken.flat_width));
    }
    this.flat = flat;
    this.broken = broken;
  }

  render(out, indent, column, width) {
    // The key to the efficiency of this whole pretty printing algorithm
    // is the fact that this conditional does not rely on rendering `this.flat`:
    let flat_width = this.flat.flat_width;
    if (flat_width !== null && column + flat_width <= width) {
      // If the "flat" doc fits on the line, use it.
      return this.flat.render(out, indent, column, width);
    } else {
      // Otherwise, use the "broken" doc.
      return this.broken.render(out, indent, column, width);
    }
  }
}

/******************************************************************************
 * String Templates
 ******************************************************************************/

function pretty(strs, ...vals) {
  // Interpret a JS string template as a pretty printing Doc.
  let lines = new Array(); // The lines will be joined with `vert`.
  let lineParts = new Array(); // The parts of each line will be joined with `horz`.
  // Iterate over the parts of the template in order.
  for (let i = 0; i < strs.length + vals.length; i++) {
    if (i % 2 === 0) {
      // It's a string part. Split it into lines.
      let parts = strs[i / 2].split("\n");
      for (let j in parts) {
        let part = parts[j];
        // For every newline in the string, push a line.
        if (j != 0) {
          lines.push(horz.apply(null, lineParts));
          lineParts = new Array();
        }
        // The string must be wrapped in `txt` to become a Doc.
        lineParts.push(txt(part));
      }
    } else {
      // It's a value part. Add it.
      lineParts.push(vals[(i - 1) / 2]);
    }
  }
  // Remember to push the last line.
  lines.push(horz.apply(null, lineParts));
  return vert.apply(null, lines);
}

/******************************************************************************
 * Private Helper Functions
 ******************************************************************************/

// The user has given us a thing. If they were nice, it would be a Doc.
// But they're not nice, so it could be anything.
// Let's see if we can make it into a Doc.
function coerce(thing) {
  if (thing instanceof Doc) {
    return thing;
  } else if (typeof thing === "string") {
    return txt(thing);
  } else if (thing != null && typeof thing.pretty === "function") {
    let doc = thing.pretty();
    if (!(doc instanceof Doc)) {
      // TODO: `+ thing` is an awful way to print something; replace with something better?
      throw new Error(
        "The pretty printer called the `.pretty()` function, and expected it to return a Doc, but instead it returned: " +
          thing,
      );
    }
    return doc;
  } else {
    // What did they give us? We can't work with this thing.
    throw new Error(
      "The pretty printer was expecting a Doc (or a String, or something with a pretty() method), but instead it was given: " +
        thing,
    );
  }
}

function intersperse(sep, items) {
  let array = new Array();
  items.forEach((item, i) => {
    if (i != 0) {
      array.push(sep);
    }
    array.push(item);
  });
  return array;
}

/******************************************************************************
 * Utility Constructors
 ******************************************************************************/

// Display all items, with each pair of adjacent items separated
// either by `sep` or by `vertSep\n`. If `sep` is txt(" ") and
// `vertSep` is txt(""), this implements word wrap.
// Neither `sep` nor `vertSep` may contain newlines.
function wrap(words, sep = " ", vertSep = "") {
  if (words.length == 0) {
    return txt("");
  }
  return words.reduce((paragraph, word) =>
    concat(paragraph, ifFlat(horz(sep, word), vert(vertSep, word))),
  );
}

// Display either `items[0] sep items[1] sep ... items[n]`
// or `items[0] vertSep \n items[1] vertSep \n ... items[n]`.
// Neither `sep` nor `vertSep` may contain newlines.
function sepBy(items, sep = " ", vertSep = "") {
  let vertItems = items.map((item, i) => {
    return i == items.length - 1 ? item : horz(item, vertSep);
  });
  return ifFlat(horzArray(intersperse(sep, items)), vertArray(vertItems));
}

function parens(center) {
  return horz("(", center, ")");
}

function standardSexpr(func, args) {
  return parens(sepBy([func].concat(args), " "));
}

function lambdaLikeSexpr(keyword, defn, body) {
  return ifFlat(
    parens(sepBy([keyword, defn, body], " ")),
    parens(vert(horz(keyword, " ", defn), horz(" ", body))),
  );
}

function beginLikeSexpr(keyword, bodies) {
  return parens(vert(keyword, horz(" ", vertArray(bodies))));
}

module.exports = {
  txt,
  horz,
  horzArray,
  vert,
  vertArray,
  concat,
  concatArray,
  ifFlat,
  fullLine,
  Doc,
  pretty,
  wrap,
  sepBy,
  standardSexpr,
  lambdaLikeSexpr,
  beginLikeSexpr,
};
