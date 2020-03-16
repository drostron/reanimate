{-# LANGUAGE MultiParamTypeClasses #-}
module Reanimate.Math.SSSP where

import Reanimate.Math.Common
import Reanimate.Math.EarClip
import qualified Data.Vector as V
import Data.Maybe
import Data.Tuple
import qualified Data.Map as Map
import Linear.Metric
import Linear.V2
import Data.List
import Debug.Trace
import qualified Data.FingerTree as F
import Data.FingerTree (SearchResult(..), search, (|>), (<|))

type SSSP = V.Vector Int

visibleFrom :: Int -> Polygon -> [Int]
visibleFrom y p =
  [ i
  | i <- [0.. n-1]
  , i /= y
  , let py = pAccess p y
        pyn = pAccess p $ pNext p y
        pyp = pAccess p $ pPrev p y
        pi = pAccess p i
        isOpen = isRightTurn pyp py pyn
  , pNext p y == i || pPrev p y == i || if isOpen
    then isLeftTurnOrLinear py pyn pi ||
         isLeftTurnOrLinear pyp py pi
    else not $ isRightTurn py pyn pi ||
               isRightTurn pyp py pi
  , let myEdges = [(e1,e2) | (e1,e2) <- edges, e1/=y, e1/=i, e2/=y,e2/=i]
  , all (isNothing . lineIntersect (elt,p V.! i))
          [ (p V.! e1,p V.! e2) | (e1,e2) <- myEdges ]]
  where
    n = length p
    elt = pAccess p y
    edges = zip [0..n-1] (tail [0..n-1] ++ [0])

-- O(n^3 log n)
naive :: Polygon -> SSSP
naive p =
    V.fromList $ Map.elems $
    Map.map (fromMaybe 0 . listToMaybe) $
    worker initial [0]
  where
    initial = Map.singleton 0 []
    worker :: Map.Map Int [Int] -> [(Int)] -> Map.Map Int [Int]
    worker m [] = m
    worker m (i:xs) =
      let vs :: [Int]
          vs = visibleFrom i p
          m' = Map.fromList
            [ (v, i : (m Map.! i))
            | v <- vs ]
      in worker (Map.unionWith f m m') (xs ++ filter (flip Map.notMember m) vs)
    pathLength [] = 0
    pathLength [v] = distance (p V.! v) (p V.! 0)
    pathLength (x:y:xs) = distance (p V.! x) (p V.! y) + pathLength (y:xs)
    f a b =
        case compare (pathLength a) (pathLength b) of
          LT -> a
          _  -> b

type Triangle = (P,P,P)
-- Dual of triangulated polygon
data Dual = Dual (Int,Int,Int) -- (a,b,c)
                  DualTree -- borders ca
                  DualTree -- borders bc
  deriving (Show)

data DualTree
  = EmptyDual
  | NodeLeaf Int
  | NodeDual Int -- axb triangle, a and b are from parent.
      DualTree -- borders ba
      DualTree -- borders xb
  | NodeDualL Int DualTree
  | NodeDualR Int DualTree
  deriving (Show)

-- Dual path:
-- (Int,Int,Int) + V.Vector Int + V.Vector LeftOrRight

simplifyDual :: DualTree -> DualTree
simplifyDual (NodeDual x EmptyDual EmptyDual) = NodeLeaf x
simplifyDual (NodeDual x l EmptyDual) = NodeDualL x l
simplifyDual (NodeDual x EmptyDual r) = NodeDualR x r
simplifyDual dual = dual

dual :: Triangulation -> Dual
dual t =
  case t V.! 0 of
    [] -> Dual (0,1,V.length t-1) EmptyDual (dualTree t (1, (V.length t-1)) 0)
    (x:_) -> Dual (0,1,x) (dualTree t (x,0) 1) (dualTree t (1,x) 0)

dualTree :: Triangulation -> (Int,Int) -> Int -> DualTree
dualTree t (a,b) e = -- simplifyDual $
    case hasTriangle of
      [] -> EmptyDual
      [(ab)] ->
        NodeDual ab (dualTree t (ab,b) a) (dualTree t (a,ab) b)
      _ -> error "Invalid triangulation"
  where
    hasTriangle = nub $ (findTriangles a b) ++ (findTriangles b a)
    n = V.length t
    next x = (x+1) `mod` n
    prev x = (x-1) `mod` n
    -- Find diagonals of 'f'
    -- that are next to 'g' (+1 or -1, mod n)
    findTriangles f g
      | next f == prev g && next f /= e = [next f]
      | next g == prev f && next g /= e = [next g]
    findTriangles f g =
      [ v | v <- t V.! f
      , v /= e , v == next g || v == prev g ]

data MinMax = MinMax Int Int | MinMaxEmpty deriving (Show)
instance Semigroup MinMax where
  MinMaxEmpty <> b = b
  a <> MinMaxEmpty = a
  MinMax a b <> MinMax c d = MinMax (min a c) (max b d)
instance Monoid MinMax where
  mempty = MinMaxEmpty

instance F.Measured MinMax Int where
  measure i = MinMax i i

-- Return True if '3' is part of 'a'.
searchFn MinMaxEmpty _ = False
searchFn (MinMax a b) _ = b >= negate 300

--toDualTree (Dual (a,b,c) l r) = NodeDual c l r
-- O(n)
sssp :: Polygon -> Dual -> SSSP
sssp p (Dual (a,b,c) l r) = toSSSP $
    (a, a) :
    (b, a) :
    (c, a) :
    worker (F.singleton c) (F.singleton b) a r ++
    loopLeft c l
  where
    toSSSP = V.fromList . map snd . sortOn fst
    loopLeft outer l =
      case l of
        EmptyDual -> []
        NodeDual x l' r' ->
          worker (F.singleton x) (F.singleton outer) a r' ++
          loopLeft x l'
    searchFn cusp x MinMaxEmpty _ = False
    searchFn cusp x (MinMax a b) _ =
      isLeftTurn (p V.! cusp) (p V.! b) (p V.! x)
    searchFn2 cusp x _ MinMaxEmpty = True
    searchFn2 cusp x _ (MinMax a b) =
      isLeftTurn (p V.! cusp) (p V.! a) (p V.! x)
    worker _ _ _ EmptyDual = []
    worker f1 f2 cusp (NodeDual x l r) =
        -- trace ("Funnel: " ++ show (f1,cusp,f2)) $
        case F.search (searchFn cusp x) f1 of
          Position f1Hi v f1Lo ->
            -- trace ("To the left") $
            (x, v::Int) :
            worker f1Hi (F.singleton x) v l ++
            worker (x <| v <| f1Lo) f2 cusp r
          OnRight ->
            case F.search (searchFn2 cusp x) f2 of
              OnLeft ->
                --trace ("Visble from cusp") $
                (x, cusp::Int) :
                worker f1 (F.singleton x) cusp l ++
                worker (F.singleton x) f2 cusp r
              Position f2Lo v f2Hi ->
                -- trace ("To the right") $
                (x, v::Int) :
                worker f1 (f2Lo |> v |> x) cusp l ++
                worker (F.singleton x) f2Hi v r
              -- OnRight ->
              --   case F.viewr f2 of
              --     F.EmptyR -> error "emptyR"
              --     f2Lo F.:> v ->
              --       trace ("To the far right") $
              --       (x, v) :
              --       worker f1 (f2Lo |> v |> x) cusp l ++
              --       worker (F.singleton x) F.empty v r
              e -> error $ "Unhandled: " ++ show e
{-
(7,0)
(1,0)
funnel: 7,0  0  0,1
2 is neither to the left of the left funnel or to the right of the right funnel,
therefore it is visible from 0.
(2,0)

-}
