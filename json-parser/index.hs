-- # A JSON parser in Haskell
--
-- **License:** MIT
--
-- **Copyright:** (c) 2025 [Abhinav Sarkar](https://abhinavsarkar.net), Google
--
-- This is a [JSON](https://en.wikipedia.org/wiki/JSON) parser written from scratch in [Haskell](https://www.haskell.org/)
-- in under 200 lines. It complies with the JSON language specification set out in [IETF RFC 8259](https://tools.ietf.org/html/rfc8259),
-- and passes the comprehensive [JSON test suite](https://github.com/nst/JSONTestSuite).
--
-- It is a recursive-descent parser, written in [Parser combinator](https://en.wikipedia.org/wiki/Parser_combinator)
-- style.
--
-- Compile it with [GHC](https://www.haskell.org/ghc/) by running:
--
-- ```shell
-- ghc --make *.hs -main-is JSONParser -o jsonparser
-- ```
--
-- This parser has been extracted and simplified from Abhinav's blog post
-- [JSON Parsing from Scratch in Haskell](https://abhinavsarkar.net/posts/json-parsing-from-scratch-in-haskell/).
-- -----------------
module JSONParser where

import Control.Applicative (Alternative (..), optional)
import Control.Monad (replicateM)
import Data.Bits (shiftL)
import Data.Char (chr, digitToInt, isDigit, isHexDigit, ord)
import Data.Functor (($>))
import System.Exit (exitFailure)

-- The data type for representing a JSON value in Haskell.
data JValue
  =
  -- Null, a null value.
    JNull
  -- Boolean, a boolean value.
  | JBool Bool
  -- String, a string value, a sequence of zero or more Unicode characters.
  | JString String
  -- Number, a numeric value representing integral and real numbers with support for scientific notation.
  | JNumber {int :: Integer, frac :: [Int], exponent :: Integer}
  -- Array, an ordered list of values.
  | JArray [JValue]
  -- Object, a collection of name-value pairs.
  | JObject [(String, JValue)]
  deriving (Eq)

-- A generic parser type. It takes some input `i`, reads some part of it, and optionally parses it into some
-- relevant data structure `o` and the rest of the input `i` to be potentially parsed later. It may fail as well.
newtype Parser i o = Parser {runParser :: i -> Maybe (i, o)}

-- A `Parser` is a [`Functor`](https://hackage.haskell.org/package/base/docs/Data-Functor.html#t:Functor).
-- This allows us to modify the result of a parser without changing the structure of the result (a parse success stays
-- a success, and a failure stays a failure).
instance Functor (Parser i) where
  fmap f parser = Parser $ fmap (fmap f) . runParser parser

-- A `Parser` is an [`Applicative`](https://hackage.haskell.org/package/base/docs/Control-Applicative.html#t:Applicative).
-- This allows us to combine the results of two parsers that are independent of each-other.
instance Applicative (Parser i) where
  pure x = Parser $ pure . (,x)
  pf <*> po = Parser $ \input -> case runParser pf input of
    Nothing -> Nothing
    Just (rest, f) -> fmap f <$> runParser po rest

-- A `Parser` is an [`Alternative`](https://hackage.haskell.org/package/base/docs/Control-Applicative.html#t:Alternative).
-- This allows us to fallback upon a second parser in case our first parser fails.
instance Alternative (Parser i) where
  empty = Parser $ const empty
  p1 <|> p2 = Parser $ \input -> runParser p1 input <|> runParser p2 input

-- A `Parser` is [`Monad`](https://hackage.haskell.org/package/base/docs/Control-Monad.html#t:Monad).
-- This allows us to combine the results of two parsers sequentially, such that one parser is
-- dependent on the result of other.
instance Monad (Parser i) where
  p >>= f = Parser $ \input -> case runParser p input of
    Nothing -> Nothing
    Just (rest, o) -> runParser (f o) rest

-- A parser that succeeds if the first element of its input list matches the given predicate.
-- Returns the matching element on success.
satisfy :: (a -> Bool) -> Parser [a] a
satisfy predicate = Parser $ \input -> case input of
  (x : xs) | predicate x -> Just (xs, x)
  _ -> Nothing

-- A parser that matches the first character of its input string with a given character.
char :: Char -> Parser String Char
char c = satisfy (== c)

-- A parser that succeeds if the first character of its input string is a digit (0–9).
digit :: Parser String Int
digit = digitToInt <$> satisfy isDigit

-- A parser that matches its input string with a given string.
string :: String -> Parser String String
string "" = pure ""
string (c : cs) = (:) <$> char c <*> string cs

-- The parser for JSON `null` value that matches the string "null", and returns the `JNull` value on
-- success.
jNull :: Parser String JValue
jNull = string "null" $> JNull

-- The parser for JSON boolean values that matches the strings "true" or "false", and returns the
-- corresponding `JBool` value on success.
jBool :: Parser String JValue
jBool =
  string "true" $> JBool True
  <|> string "false" $> JBool False

-- The parser for JSON characters that matches ASCII characters, as well as, escaped sequences
-- for characters defined in the JSON spec, and Unicode characters with `\u` prefix and their hex-digit codes.
jsonChar :: Parser String Char
jsonChar =
  string "\\\"" $> '"'
  <|> string "\\\\" $> '\\'
  <|> string "\\/" $> '/'
  <|> string "\\b" $> '\b'
  <|> string "\\f" $> '\f'
  <|> string "\\n" $> '\n'
  <|> string "\\r" $> '\r'
  <|> string "\\t" $> '\t'
  <|> unicodeChar
  <|> satisfy (\c -> not (c == '\"' || c == '\\' || isControl c))
  where
    unicodeChar =
      chr . fromIntegral . digitsToNumber 16 0
        <$> (string "\\u" *> replicateM 4 hexDigit)

    hexDigit = digitToInt <$> satisfy isHexDigit

    isControl c = c `elem` ['\0' .. '\31']

digitsToNumber :: Int -> Integer -> [Int] -> Integer
digitsToNumber base =
  foldl (\num d -> num * fromIntegral base + fromIntegral d)

-- The parser for JSON strings that takes care of correctly parsing [UTF-16 surrogate pairs](https://en.wikipedia.org/wiki/UTF-16#Code_points_from_U+010000_to_U+10FFFF).
jString :: Parser String JValue
jString = JString <$> (char '"' *> jString')
  where
    jString' = do
      optFirst <- optional jsonChar
      case optFirst of
        Nothing -> char '"' $> ""
        Just first | not (isSurrogate first) -> (first :) <$> jString'
        Just first -> do
          second <- jsonChar
          if isHighSurrogate first && isLowSurrogate second
            then (combineSurrogates first second :) <$> jString'
            else empty

    isHighSurrogate a =
      ord a >= highSurrogateLowerBound && ord a <= highSurrogateUpperBound
    isLowSurrogate a =
      ord a >= lowSurrogateLowerBound && ord a <= lowSurrogateUpperBound
    isSurrogate a = isHighSurrogate a || isLowSurrogate a

    combineSurrogates a b =
      chr $
        ((ord a - highSurrogateLowerBound) `shiftL` 10)
          + (ord b - lowSurrogateLowerBound)
          + 0x10000

    highSurrogateLowerBound = 0xD800
    highSurrogateUpperBound = 0xDBFF
    lowSurrogateLowerBound = 0xDC00
    lowSurrogateUpperBound = 0xDFFF

-- The parser for JSON numbers in integer, decimal or scientific notation formats.
jNumber :: Parser String JValue
jNumber = jIntFracExp <|> jIntExp <|> jIntFrac <|> jInt
  where
    jInt = JNumber <$> jInt' <*> pure [] <*> pure 0
    jIntExp = JNumber <$> jInt' <*> pure [] <*> jExp
    jIntFrac = (\i f -> JNumber i f 0) <$> jInt' <*> jFrac
    jIntFracExp = (\ ~(JNumber i f _) e -> JNumber i f e) <$> jIntFrac <*> jExp

    jInt' = signInt <$> optional (char '-') <*> jUInt
    jUInt =
      (\d ds -> digitsToNumber 10 0 (d : ds)) <$> digit19 <*> digits
      <|> fromIntegral <$> digit

    jFrac = char '.' *> digits
    jExp =
      (char 'e' <|> char 'E')
        *> (signInt <$> optional (char '+' <|> char '-') <*> jUInt)

    digit19 = digitToInt <$> satisfy (\x -> isDigit x && x /= '0')
    digits = some digit

    signInt (Just '-') i = negate i
    signInt _ i = i

-- Some handy parser combinators.
surroundedBy :: Parser i a -> Parser i b -> Parser i a
surroundedBy p1 p2 = p2 *> p1 <* p2

separatedBy :: Parser i v -> Parser i s -> Parser i [v]
separatedBy v s =
  (:) <$> v <*> many (s *> v)
  <|> pure []

between :: Parser i a -> Parser i a -> Parser i b -> Parser i b
between pl pr p = pl *> p <* pr

spaces :: Parser String String
spaces = many (char ' ' <|> char '\n' <|> char '\r' <|> char '\t')

-- The parser for JSON arrays, containing zero or more items of any JSON types separated by commas.
jArray :: Parser String JValue
jArray = fmap JArray
  $ between (char '[') (char ']')
  $ jValue `separatedBy` char ',' `surroundedBy` spaces

-- The parser for JSON objects, containing  zero or more key-value pairs separated by colon, where
-- keys are JSON strings, and values are any JSON types.
jObject :: Parser String JValue
jObject = fmap JObject
  $ between (char '{') ( char '}')
  $ pair `separatedBy` char ',' `surroundedBy` spaces
  where
    pair =
      (\ ~(JString s) j -> (s, j))
        <$> (jString `surroundedBy` spaces)
        <* char ':'
        <*> jValue

-- The parser for any JSON value, created by combining all the previous JSON parsers.
jValue :: Parser String JValue
jValue = jValue' `surroundedBy` spaces
  where
    jValue' =
      jNull
        <|> jBool
        <|> jString
        <|> jNumber
        <|> jArray
        <|> jObject

-- `parseJSON` parses its input string as a JSON value, or fails on parsing errors.
parseJSON :: String -> Maybe JValue
parseJSON s = case runParser jValue s of
  Just ("", j) -> Just j
  _ -> Nothing

-- `main` function reads text from standard input, and parses it as a JSON value.
-- Prints a message indicating whether parsing succeeded or failed.
main :: IO ()
main =
  getContents >>= \input -> case parseJSON input of
    Just _ -> putStrLn "Parse okay"
    Nothing -> putStrLn "Parse failed" >> exitFailure
