{-# LANGUAGE FlexibleContexts, TupleSections #-}

module HSE.Util(module HSE.Util, def) where

import Control.Monad
import Data.Default
import Data.Tuple.Extra
import Data.List
import Language.Haskell.Exts.Util
import Control.Monad.Trans.State
import qualified Data.Map as Map
import Data.Maybe
import Data.Data hiding (Fixity)
import System.FilePath
import HSE.Type
import Data.Functor
import Prelude


---------------------------------------------------------------------
-- ACCESSOR/TESTER

ellipses :: QName S
ellipses = UnQual an $ Ident an "..." -- Must be an Ident, not a Symbol

opExp :: QOp S -> Exp_
opExp (QVarOp s op) = Var s op
opExp (QConOp s op) = Con s op

expOp :: Exp_ -> Maybe (QOp S)
expOp (Var s op) = Just $ QVarOp s op
expOp (Con s op) = Just $ QConOp s op
expOp _ = Nothing

moduleDecls :: Module_ -> [Decl_]
moduleDecls (Module _ _ _ _ xs) = xs
moduleDecls _ = [] -- XmlPage/XmlHybrid

moduleName :: Module_ -> String
moduleName (Module _ Nothing _ _ _) = "Main"
moduleName (Module _ (Just (ModuleHead _ (ModuleName _ x) _ _)) _ _ _) = x
moduleName _ = "" -- XmlPage/XmlHybrid

moduleImports :: Module_ -> [ImportDecl S]
moduleImports (Module _ _ _ x _) = x
moduleImports _ = [] -- XmlPage/XmlHybrid

modulePragmas :: Module_ -> [ModulePragma S]
modulePragmas (Module _ _ x _ _) = x
modulePragmas _ = [] -- XmlPage/XmlHybrid

moduleExtensions :: Module_ -> [Name S]
moduleExtensions x = concat [y | LanguagePragma _ y <- modulePragmas x]

fromModuleName :: ModuleName S -> String
fromModuleName (ModuleName _ x) = x

fromChar :: Exp_ -> Maybe Char
fromChar (Lit _ (Char _ x _)) = Just x
fromChar _ = Nothing

fromPChar :: Pat_ -> Maybe Char
fromPChar (PLit _ _ (Char _ x _)) = Just x
fromPChar _ = Nothing

fromString :: Exp_ -> Maybe String
fromString (Lit _ (String _ x _)) = Just x
fromString _ = Nothing

fromPString :: Pat_ -> Maybe String
fromPString (PLit _ _ (String _ x _)) =  Just x
fromPString _ = Nothing

fromParen1 :: Exp_ -> Exp_
fromParen1 (Paren _ x) = x
fromParen1 x = x

fromParen :: Exp_ -> Exp_
fromParen (Paren _ x) = fromParen x
fromParen x = x

fromPParen :: Pat s -> Pat s
fromPParen (PParen _ x) = fromPParen x
fromPParen x = x

fromTyParen :: Type s -> Type s
fromTyParen (TyParen _ x) = fromTyParen x
fromTyParen x = x

fromTyBang :: Type s -> Type s
fromTyBang (TyBang _ _ _ x) = x
fromTyBang x = x

-- is* :: Exp_ -> Bool
-- is* :: Decl_ -> Bool
isVar Var{} = True; isVar _ = False
isCon Con{} = True; isCon _ = False
isApp App{} = True; isApp _ = False
isInfixApp InfixApp{} = True; isInfixApp _ = False
isAnyApp x = isApp x || isInfixApp x
isParen Paren{} = True; isParen _ = False
isIf If{} = True; isIf _ = False
isLambda Lambda{} = True; isLambda _ = False
isMDo MDo{} = True; isMDo _ = False
isBoxed Boxed{} = True; isBoxed _ = False
isDerivDecl DerivDecl{} = True; isDerivDecl _ = False
isPBangPat PBangPat{} = True; isPBangPat _ = False
isPFieldPun PFieldPun{} = True; isPFieldPun _ = False
isFieldPun FieldPun{} = True; isFieldPun _ = False
isPWildCard PWildCard{} = True; isPWildCard _ = False
isPFieldWildcard PFieldWildcard{} = True; isPFieldWildcard _ = False
isFieldWildcard FieldWildcard{} = True; isFieldWildcard _ = False
isPViewPat PViewPat{} = True; isPViewPat _ = False
isParComp ParComp{} = True; isParComp _ = False
isTypeApp TypeApp{} = True; isTypeApp _ = False
isPatTypeSig PatTypeSig{} = True; isPatTypeSig _ = False
isQuasiQuote QuasiQuote{} = True; isQuasiQuote _ = False
isTyQuasiQuote TyQuasiQuote{} = True; isTyQuasiQuote _ = False
isSpliceDecl SpliceDecl{} = True; isSpliceDecl _ = False
isNewType NewType{} = True; isNewType _ = False
isRecStmt RecStmt{} = True; isRecStmt _ = False
isClsDefSig ClsDefSig{} = True; isClsDefSig _ = False
isTyBang TyBang{} = True; isTyBang _ = False
isLCase LCase{} = True; isLCase _ = False
isTupleSection TupleSection{} = True; isTupleSection _ = False
isString String{} = True; isString _ = False
isRecUpdate RecUpdate{} = True; isRecUpdate _ = False
isRecConstr RecConstr{} = True; isRecConstr _ = False

isSection LeftSection{} = True
isSection RightSection{} = True
isSection _ = False

isPrimLiteral PrimInt{} = True
isPrimLiteral PrimWord{} = True
isPrimLiteral PrimFloat{} = True
isPrimLiteral PrimDouble{} = True
isPrimLiteral PrimChar{} = True
isPrimLiteral PrimString{} = True
isPrimLiteral _ = False


allowRightSection x = x `notElem` ["-","#"]
allowLeftSection x = x /= "#"


unqual :: QName S -> QName S
unqual (Qual an _ x) = UnQual an x
unqual x = x

fromQual :: QName a -> Maybe (Name a)
fromQual (Qual _ _ x) = Just x
fromQual (UnQual _ x) = Just x
fromQual _ = Nothing

isSpecial :: QName S -> Bool
isSpecial Special{} = True; isSpecial _ = False

isDol :: QOp S -> Bool
isDol (QVarOp _ (UnQual _ (Symbol _ "$"))) = True
isDol _ = False

isDot :: QOp S -> Bool
isDot (QVarOp _ (UnQual _ (Symbol _ "."))) = True
isDot _ = False

isDotApp :: Exp_ -> Bool
isDotApp (InfixApp _ _ dot _) | isDot dot = True
isDotApp _ = False

dotApp :: Exp_ -> Exp_ -> Exp_
dotApp x = InfixApp an x (QVarOp an $ UnQual an $ Symbol an ".")

dotApps :: [Exp_] -> Exp_
dotApps [] = error "HSE.Util.dotApps, does not work on an empty list"
dotApps [x] = x
dotApps (x:xs) = dotApp x (dotApps xs)

isReturn :: Exp_ -> Bool
-- Allow both pure and return, as they have the same semantics
isReturn (Var _ (UnQual _ (Ident _ x))) = x == "return" || x == "pure"
isReturn _ = False

isLexeme Var{} = True
isLexeme Con{} = True
isLexeme Lit{} = True
isLexeme _ = False

isAssocLeft AssocLeft{} = True; isAssocLeft _ = False
isAssocNone AssocNone{} = True; isAssocNone _ = False

isWHNF :: Exp_ -> Bool
isWHNF Con{} = True
isWHNF (Lit _ x) = case x of String{} -> False; Int{} -> False; Frac{} -> False; _ -> True
isWHNF Lambda{} = True
isWHNF Tuple{} = True
isWHNF List{} = True
isWHNF (Paren _ x) = isWHNF x
isWHNF (ExpTypeSig _ x _) = isWHNF x
-- other (unknown) constructors may have bang patterns in them, so approximate
isWHNF (App _ c@Con{} _) | prettyPrint c `elem` ["Just","Left","Right"] = True
isWHNF _ = False


-- | Like needBracket, but with a special case for a . b . b, which
--   was removed from haskell-src-exts-util-0.2.2
needBracketOld :: Int -> Exp_ -> Exp_ -> Bool
needBracketOld i parent child
    | isDotApp parent, isDotApp child, i == 1 = False
    | otherwise = needBracket i parent child

transformBracketOld :: (Exp_ -> Maybe Exp_) -> Exp_ -> Exp_
transformBracketOld op = snd . g
    where
        g = f . descendBracketOld g
        f x = maybe (False,x) (True,) (op x)

-- | Descend, and if something changes then add/remove brackets appropriately
descendBracketOld :: (Exp_ -> (Bool, Exp_)) -> Exp_ -> Exp_
descendBracketOld op x = descendIndex g x
    where
        g i y = if a then f i b else b
            where (a,b) = op y

        f i (Paren _ y) | not $ needBracketOld i x y = y
        f i y           | needBracketOld i x y = addParen y
        f _ y           = y

descendIndex :: Data a => (Int -> a -> a) -> a -> a
descendIndex f x = flip evalState 0 $ flip descendM x $ \y -> do
    i <- get
    modify (+1)
    return $ f i y


---------------------------------------------------------------------
-- HSE FUNCTIONS

getEquations :: Decl s -> [Decl s]
getEquations (FunBind s xs) = map (FunBind s . (:[])) xs
getEquations x@PatBind{} = [toFunBind x]
getEquations x = [x]


toFunBind :: Decl s -> Decl s
toFunBind (PatBind s (PVar _ name) bod bind) = FunBind s [Match s name [] bod bind]
toFunBind x = x


-- case and if both have branches, nothing else does
replaceBranches :: Exp s -> ([Exp s], [Exp s] -> Exp s)
replaceBranches (If s a b c) = ([b,c], \[b,c] -> If s a b c)
replaceBranches (Case s a bs) = (concatMap f bs, Case s a . g bs)
    where
        f (Alt _ _ (UnGuardedRhs _ x) _) = [x]
        f (Alt _ _ (GuardedRhss _ xs) _) = [x | GuardedRhs _ _ x <- xs]
        g (Alt s1 a (UnGuardedRhs s2 _) b:rest) (x:xs) = Alt s1 a (UnGuardedRhs s2 x) b : g rest xs
        g (Alt s1 a (GuardedRhss s2 ns) b:rest) xs =
                Alt s1 a (GuardedRhss s2 [GuardedRhs a b x | (GuardedRhs a b _,x) <- zip ns as]) b : g rest bs
            where (as,bs) = splitAt (length ns) xs
        g [] [] = []
        g _ _ = error "HSE.Util.replaceBranches: internal invariant failed, lists are of differing lengths"
replaceBranches x = ([], \[] -> x)


---------------------------------------------------------------------
-- VECTOR APPLICATION


apps :: [Exp_] -> Exp_
apps = foldl1 (App an)

fromApps :: Exp_ -> [Exp_]
fromApps = map fst . fromAppsWithLoc

fromAppsWithLoc :: Exp_ -> [(Exp_, S)]
fromAppsWithLoc (App l x y) = fromAppsWithLoc x ++ [(y, l)]
fromAppsWithLoc x = [(x, ann x)]


-- Rule for the Uniplate Apps functions
-- Given (f a) b, consider the children to be: children f ++ [a,b]

childrenApps :: Exp_ -> [Exp_]
childrenApps (App s x y) = childrenApps x ++ [y]
childrenApps x = children x


descendApps :: (Exp_ -> Exp_) -> Exp_ -> Exp_
descendApps f (App s x y) = App s (descendApps f x) (f y)
descendApps f x = descend f x


descendAppsM :: Monad m => (Exp_ -> m Exp_) -> Exp_ -> m Exp_
descendAppsM f (App s x y) = liftM2 (App s) (descendAppsM f x) (f y)
descendAppsM f x = descendM f x


universeApps :: Exp_ -> [Exp_]
universeApps x = x : concatMap universeApps (childrenApps x)

transformApps :: (Exp_ -> Exp_) -> Exp_ -> Exp_
transformApps f = f . descendApps (transformApps f)

transformAppsM :: Monad m => (Exp_ -> m Exp_) -> Exp_ -> m Exp_
transformAppsM f x = f =<< descendAppsM (transformAppsM f) x


---------------------------------------------------------------------
-- UNIPLATE FUNCTIONS

universeS :: (Data x, Data (f S)) => x -> [f S]
universeS = universeBi

childrenS :: (Data x, Data (f S)) => x -> [f S]
childrenS = childrenBi


-- return the parent along with the child
universeParentExp :: Data a => a -> [(Maybe (Int, Exp_), Exp_)]
universeParentExp xs = concat [(Nothing, x) : f x | x <- childrenBi xs]
    where f p = concat [(Just (i,p), c) : f c | (i,c) <- zip [0..] $ children p]


---------------------------------------------------------------------
-- SRCLOC FUNCTIONS

showSrcLoc :: SrcLoc -> String
showSrcLoc (SrcLoc file line col) = take 1 file ++ f (drop 1 file) ++ ":" ++ show line ++ ":" ++ show col
    where f (x:y:zs) | isPathSeparator x && isPathSeparator y = f $ x:zs
          f (x:xs) = x : f xs
          f [] = []

an :: SrcSpanInfo
an = def

dropAnn :: Functor f => f SrcSpanInfo -> f ()
dropAnn = void

---------------------------------------------------------------------
-- SRCLOC EQUALITY

-- enforce all being on S, as otherwise easy to =~= on a Just, and get the wrong functor

x /=~= y = not $ x =~= y

elem_, notElem_ :: (Annotated f, Eq (f ())) => f S -> [f S] -> Bool
elem_ x = any (x =~=)
notElem_ x = not . elem_ x

nub_ :: (Annotated f, Eq (f ())) => [f S] -> [f S]
nub_ = nubBy (=~=)

delete_ :: (Annotated f, Eq (f ())) => f S -> [f S] -> [f S]
delete_ = deleteBy (=~=)

intersect_ :: (Annotated f, Eq (f ())) => [f S] -> [f S] -> [f S]
intersect_ = intersectBy (=~=)

eqList, neqList :: (Annotated f, Eq (f ())) => [f S] -> [f S] -> Bool
neqList x y = not $ eqList x y
eqList (x:xs) (y:ys) = x =~= y && eqList xs ys
eqList [] [] = True
eqList _ _ = False

eqMaybe:: (Annotated f, Eq (f ())) => Maybe (f S) -> Maybe (f S) -> Bool
eqMaybe (Just x) (Just y) = x =~= y
eqMaybe Nothing Nothing = True
eqMaybe _ _ = False


---------------------------------------------------------------------
-- FIXITIES

getFixity :: Decl a -> [Fixity]
getFixity (InfixDecl sl a mp ops) = [Fixity (void a) (fromMaybe 9 mp) (UnQual () $ void $ f op) | op <- ops]
    where f (VarOp _ x) = x
          f (ConOp _ x) = x
getFixity _ = []

toInfixDecl :: Fixity -> Decl ()
toInfixDecl (Fixity a b c) = InfixDecl () a (Just b) $ maybeToList $ VarOp () <$> fromQual c



-- | This extension implies the following extensions
extensionImplies :: Extension -> [Extension]
extensionImplies = \x -> Map.findWithDefault [] x mp
    where mp = Map.fromList extensionImplications

-- | This extension is implied by the following extensions
extensionImpliedBy :: Extension -> [Extension]
extensionImpliedBy = \x -> Map.findWithDefault [] x mp
    where mp = Map.fromListWith (++) [(b, [a]) | (a,bs) <- extensionImplications, b <- bs]

-- | (a, bs) means extension a implies all of bs.
--   Taken from https://downloads.haskell.org/~ghc/master/users-guide/glasgow_exts.html#language-options
extensionImplications :: [(Extension, [Extension])]
extensionImplications = map (first EnableExtension) $
    (RebindableSyntax, [DisableExtension ImplicitPrelude]) :
    map (\(k, vs) -> (k, map EnableExtension vs))
    [ (DerivingVia              , [DerivingStrategies])
    , (RecordWildCards          , [DisambiguateRecordFields])
    , (ExistentialQuantification, [ExplicitForAll])
    , (FlexibleInstances        , [TypeSynonymInstances])
    , (FunctionalDependencies   , [MultiParamTypeClasses])
    , (GADTs                    , [MonoLocalBinds])
    , (IncoherentInstances      , [OverlappingInstances])
--    Incorrect, see https://github.com/ndmitchell/hlint/issues/587
--    , (ImplicitParams           , [FlexibleContexts, FlexibleInstances])
    , (ImpredicativeTypes       , [ExplicitForAll, RankNTypes])
    , (LiberalTypeSynonyms      , [ExplicitForAll])
    , (PolyKinds                , [KindSignatures])
    , (RankNTypes               , [ExplicitForAll])
    , (ScopedTypeVariables      , [ExplicitForAll])
    , (TypeOperators            , [ExplicitNamespaces])
    , (TypeFamilies             , [ExplicitNamespaces, KindSignatures, MonoLocalBinds])
    , (TypeFamilyDependencies   , [ExplicitNamespaces, KindSignatures, MonoLocalBinds, TypeFamilies])
    ]
