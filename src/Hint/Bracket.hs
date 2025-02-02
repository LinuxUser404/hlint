{-# LANGUAGE ViewPatterns, ScopedTypeVariables #-}
{-
Raise an error if you are bracketing an atom, or are enclosed be a list bracket

<TEST>
-- expression bracket reduction
yes = (f x) x -- @Suggestion f x x
no = f (x x)
yes = (foo) -- foo
yes = (foo bar) -- @Suggestion foo bar
yes = foo (bar) -- @Warning bar
yes = foo ((x x)) -- @Suggestion (x x)
yes = (f x) ||| y -- @Suggestion f x ||| y
yes = if (f x) then y else z -- @Suggestion if f x then y else z
yes = if x then (f y) else z -- @Suggestion if x then f y else z
yes = (a foo) :: Int -- @Suggestion a foo :: Int
yes = [(foo bar)] -- @Suggestion [foo bar]
yes = foo ((x y), z) -- @Suggestion (x y, z)
yes = C { f = (e h) } -- @Suggestion C {f = e h}
yes = \ x -> (x && x) -- @Suggestion \x -> x && x
no = \(x -> y) -> z
yes = (`foo` (bar baz)) -- @Suggestion (`foo` bar baz)
yes = f ((x)) -- @Warning x
main = do f; (print x) -- @Suggestion do f print x
yes = f (x) y -- @Warning x
no = f (+x) y
no = f ($x) y
no = ($x)
yes = (($x))
no = ($1)
yes = (($1)) -- @Warning ($1)
no = (+5)
yes = ((+5)) -- @Warning (+5)

-- type bracket reduction
foo :: (Int -> Int) -> Int
foo :: (Maybe Int) -> a -- @Suggestion Maybe Int -> a
instance Named (DeclHead S)
data Foo = Foo {foo :: (Maybe Foo)} -- @Suggestion foo :: Maybe Foo

-- pattern bracket reduction
foo (x:xs) = 1
foo (True) = 1 -- @Warning True
foo ((True)) = 1 -- @Warning True
foo (A{}) = True -- A{}
f x = case x of (Nothing) -> 1; _ -> 2 -- Nothing

-- dollar reduction tests
no = groupFsts . sortFst $ mr
yes = split "to" $ names -- split "to" names
yes = white $ keysymbol -- white keysymbol
yes = operator foo $ operator -- operator foo operator
no = operator foo $ operator bar
yes = return $ Record{a=b}

-- $/bracket rotation tests
yes = (b $ c d) ++ e -- b (c d) ++ e
yes = (a b $ c d) ++ e -- a b (c d) ++ e
no = (f . g $ a) ++ e
no = quickCheck ((\h -> cySucc h == succ h) :: Hygiene -> Bool)
foo = (case x of y -> z; q -> w) :: Int

-- backup fixity resolution
main = do a += b . c; return $ a . b

-- <$> bracket tests
yes = (foo . bar x) <$> baz q -- foo . bar x <$> baz q
no = foo . bar x <$> baz q

-- annotations
main = 1; {-# ANN module ("HLint: ignore Use camelCase" :: String) #-}
main = 1; {-# ANN module (1 + (2)) #-} -- 2

-- special case from esqueleto, see #224
main = operate <$> (select $ from $ \user -> return $ user ^. UserEmail)
-- unknown fixity, see #426
bad x = x . (x +? x . x)
-- special case people don't like to warn on
special = foo $ f{x=1}
special = foo $ Rec{x=1}
special = foo (f{x=1})
</TEST>
-}


module Hint.Bracket(bracketHint) where

import Hint.Type
import Data.Data
import Refact.Types


bracketHint :: DeclHint
bracketHint _ _ x =
    concatMap (\x -> bracket isPartialAtom True x ++ dollar x) (childrenBi (descendBi annotations x) :: [Exp_]) ++
    concatMap (bracket (const False) False) (childrenBi x :: [Type_]) ++
    concatMap (bracket (const False) False) (childrenBi x :: [Pat_]) ++
    concatMap fieldDecl (childrenBi x)
    where
        -- Brackets at the roots of annotations are fine, so we strip them
        annotations :: Annotation S -> Annotation S
        annotations = descendBi $ \x -> case (x :: Exp_) of
            Paren _ x -> x
            x -> x

isPartialAtom :: Exp_ -> Bool
isPartialAtom (SpliceExp _ IdSplice{}) = True -- might be $x, which was really $ x, but TH enabled misparsed it
isPartialAtom x = isRecConstr x || isRecUpdate x

-- Dirty, should add to Brackets type class I think
tyConToRtype :: String -> RType
tyConToRtype "Exp" = Expr
tyConToRtype "Type" = Type
tyConToRtype "Pat"  = Pattern
tyConToRtype _      = Expr

findType :: (Data a) => a -> RType
findType = tyConToRtype . dataTypeName . dataTypeOf

-- Just if at least one paren was removed
-- Nothing if zero parens were removed
remParens :: Brackets a => a -> Maybe a
remParens = fmap go . remParen
  where
    go e = maybe e go (remParen e)

bracket :: forall a . (Data (a S), ExactP a, Pretty (a S), Brackets (a S)) => (a S -> Bool) -> Bool -> a S -> [Idea]
bracket isPartialAtom root = f Nothing
    where
        msg = "Redundant bracket"

        -- f (Maybe (index, parent, gen)) child
        f :: (Data (a S), ExactP a, Pretty (a S), Brackets (a S)) => Maybe (Int,a S,a S -> a S) -> a S -> [Idea]
        f Just{} o@(remParens -> Just x) | isAtom x, not $ isPartialAtom x = bracketError msg o x : g x
        f Nothing o@(remParens -> Just x) | root || isAtom x, not $ isPartialAtom x = (if isAtom x then bracketError else bracketWarning) msg o x : g x
        f (Just (i,o,gen)) v@(remParens -> Just x) | not $ needBracket i o x, not $ isPartialAtom x =
          suggest msg o (gen x) [r] : g x
          where
            typ = findType v
            r = Replace typ (toSS v) [("x", toSS x)] "x"
        f _ x = g x

        g :: (Data (a S), ExactP a, Pretty (a S), Brackets (a S)) => a S -> [Idea]
        g o = concat [f (Just (i,o,gen)) x | (i,(x,gen)) <- zip [0..] $ holes o]

bracketWarning :: (Pretty (a1 S), Pretty (a2 SrcSpanInfo),
                    Data (a1 S), Annotated a2, Annotated a1) =>
                  String -> a2 SrcSpanInfo -> a1 S -> Idea
bracketWarning msg o x =
  suggest msg o x [Replace (findType x) (toSS o) [("x", toSS x)] "x"]

bracketError :: (Pretty (a1 S), Pretty (a2 SrcSpanInfo),
                  Data (a1 S), Annotated a2, Annotated a1) =>
                String -> a2 SrcSpanInfo -> a1 S -> Idea
bracketError msg o x =
  warn msg o x [Replace (findType x) (toSS o) [("x", toSS x)] "x"]


fieldDecl :: FieldDecl S -> [Idea]
fieldDecl o@(FieldDecl a b v@(TyParen _ c))
    = [suggest "Redundant bracket" o (FieldDecl a b c)  [Replace Type (toSS v) [("x", toSS c)] "x"]]
fieldDecl _ = []


dollar :: Exp_ -> [Idea]
dollar = concatMap f . universe
    where
        f x = [suggest "Redundant $" x y [r] | InfixApp _ a d b <- [x], opExp d ~= "$"
              ,let y = App an a b, not $ needBracket 0 y a, not $ needBracket 1 y b, not $ isPartialAtom b
              ,let r = Replace Expr (toSS x) [("a", toSS a), ("b", toSS b)] "a b"]
              ++
              [suggest "Move brackets to avoid $" x (t y) [r] |(t, e@(Paren _ (InfixApp _ a1 op1 a2))) <- splitInfix x
              ,opExp op1 ~= "$", isVar a1 || isApp a1 || isParen a1, not $ isAtom a2
              ,not $ a1 ~= "select" -- special case for esqueleto, see #224
              , let y = App an a1 (Paren an a2)
              , let r = Replace Expr (toSS e) [("a", toSS a1), ("b", toSS a2)] "a (b)" ]
              ++
              -- special case of (v1 . v2) <$> v3
              [suggest "Redundant bracket" x y []
              | InfixApp _ (Paren _ o1@(InfixApp _ v1 (isDot -> True) v2)) o2 v3 <- [x], opExp o2 ~= "<$>"
              , let y = InfixApp an o1 o2 v3]


-- return both sides, and a way to put them together again
splitInfix :: Exp_ -> [(Exp_ -> Exp_, Exp_)]
splitInfix (InfixApp s a b c) = [(InfixApp s a b, c), (\a -> InfixApp s a b c, a)]
splitInfix _ = []
