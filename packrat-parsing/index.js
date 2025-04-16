// # Packrat parsing (PEG style)
//
// This is a parser combinator library for building [packrat parsers][].
// It was submitted as part of the artifacts for the 2017 paper [Incremental
// Packrat Parsing](https://ohmjs.org/pubs/sle2017/incremental-packrat-parsing.pdf).
//
// [Source](https://github.com/ohmjs/sle17/blob/a03cbbebeb7b7f5639ee0f72b6a3aafe9247dc9d/src/standard.js)
//
// [packrat parsers]: https://en.wikipedia.org/wiki/Packrat_parser
//
// **License:** [MIT](https://github.com/ohmjs/sle17/blob/a03cbbebeb7b7f5639ee0f72b6a3aafe9247dc9d/LICENSE)<br>
// **Copyright:** (c) 2017 Patrick Dubroy and Alessandro Warth

class Matcher {
  constructor(rules) {
    this.rules = rules;
  }

  match(input) {
    this.input = input;
    this.pos = 0;
    this.memoTable = [];
    var cst =
        new RuleApplication('start').eval(this);
    if (this.pos === this.input.length) {
      return cst;
    }
    return null;
  }

  hasMemoizedResult(ruleName) {
    return !!this.memoTableAt(this.pos)[ruleName];
  }

  memoizeResult(ruleName, pos, cst) {
    var result = {
      cst: cst,
      nextPos: this.pos
    };
    this.memoTableAt(pos)[ruleName] = result;
    return result;
  }

  useMemoizedResult(ruleName) {
    var result = this.memoTableAt(this.pos)[ruleName];
    this.pos = result.nextPos;
    if (`used` in result) {
      result.used = true; // this result is a left recursion failer!
    }
    return result.cst;
  }

  consume(c) {
    if (this.input[this.pos] === c) {
      this.pos++;
      return true;
    }
    return false;
  }

  memoizeLRFailerAtCurrPos(ruleName) {
    const lrFailer = {cst: null, nextPos: -1, used: false};
    this.memoTableAt(this.pos)[ruleName] = lrFailer;
    return lrFailer;
  }

  memoTableAt(pos) {
    let memo = this.memoTable[pos];
    if (!memo) {
      memo = this.memoTable[pos] = new Map();
    }
    return memo;
  }
}

class RuleApplication {
  constructor(ruleName) {
    this.ruleName = ruleName;
  }

  eval(matcher) {
    if (matcher.hasMemoizedResult(this.ruleName)) {
      return matcher.useMemoizedResult(this.ruleName);
    }
    var origPos = matcher.pos;
    var lrFailer = matcher.memoizeLRFailerAtCurrPos(this.ruleName);
    var cst = matcher.rules[this.ruleName].eval(matcher);
    var result = matcher.memoizeResult(this.ruleName, origPos, cst);
    if (lrFailer.used) {
      do {
        result.cst = cst;
        result.nextPos = matcher.pos;
        matcher.pos = origPos;
        cst = matcher.rules[this.ruleName].eval(matcher);
      } while (cst !== null && matcher.pos > result.nextPos);
      matcher.pos = result.nextPos;
    }
    return result.cst;
  }
}

class Terminal {
  constructor(str) {
    this.str = str;
  }

  eval(matcher) {
    for (var i = 0; i < this.str.length; i++) {
      if (!matcher.consume(this.str[i])) {
        return null;
      }
    }
    return this.str;
  }
}

class Choice {
  constructor(exps) {
    this.exps = exps;
  }

  eval(matcher) {
    var origPos = matcher.pos;
    for (var i = 0; i < this.exps.length; i++) {
      matcher.pos = origPos;
      var cst = this.exps[i].eval(matcher);
      if (cst !== null) {
        return cst;
      }
    }
    return null;
  }
}

class Sequence {
  constructor(exps) {
    this.exps = exps;
  }

  eval(matcher) {
    var ans = [];
    for (var i = 0; i < this.exps.length; i++) {
      var exp = this.exps[i];
      var cst = exp.eval(matcher);
      if (cst === null) {
        return null;
      }
      if (!(exp instanceof Not)) {
        ans.push(cst);
      }
    }
    return ans;
  }
}

class Not {
  constructor(exp) {
    this.exp = exp;
  }

  eval(matcher) {
    var origPos = matcher.pos;
    if (this.exp.eval(matcher) === null) {
      matcher.pos = origPos;
      return true;
    }
    return null;
  }
}

class Repetition {
  constructor(exp) {
    this.exp = exp;
  }

  eval(matcher) {
    var ans = [];
    while (true) {
      var origPos = matcher.pos;
      var cst = this.exp.eval(matcher);
      if (cst === null) {
        matcher.pos = origPos;
        break;
      } else {
        ans.push(cst);
      }
    }
    return ans;
  }
}

// A little example w/ left recursion:

// const g = new Matcher({
//   start: new RuleApplication('mulExp'),
//   mulExp: new Choice([
//     new Sequence([
//       new RuleApplication('mulExp'),
//       new Terminal('+'),
//       new RuleApplication('priExp'),
//     ]),
//     new RuleApplication('priExp'),
//   ]),
//   priExp: new Choice([new Terminal('pi'), new Terminal('x')]),
// });

// console.log(g.match('pi+pi+x'));

// return {Matcher, Terminal, RuleApplication, Choice, Sequence, Repetition, Not};
