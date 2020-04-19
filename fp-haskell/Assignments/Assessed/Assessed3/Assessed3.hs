-- setting the "warn-incomplete-patterns" flag asks GHC to warn you
-- about possible missing cases in pattern-matching definitions
{-# OPTIONS_GHC -fwarn-incomplete-patterns #-}

-- see https://wiki.haskell.org/Safe_Haskell
{-# LANGUAGE Safe #-}

module Assessed3 where

import Data.List
import Data.Tree

import Types
import DomViz  -- comment out as a last resort if you are unable to install diagrams

-- given a cell c and a player p, compute the adjacent cell c'
-- that is also occupied if p plays a domino at c
adjCell :: Cell -> Player -> Cell
adjCell (x,y) H = (x+1,y)
adjCell (x,y) V = (x,y+1)

-- compute the opponent of a player
opp :: Player -> Player
opp H = V
opp V = H

-- determine whether a move is valid in a given board
valid :: Board -> Cell -> Bool
valid b c = c `elem` free b && adjCell c (turn b) `elem` free b

-- create an empty board from an arbitrary list of cells
empty :: [Cell] -> Board
empty cs = Board { turn = H, free = cs, hist = [] }

-- create a rectangular board of arbitrary dimensions
board :: Int -> Int -> Board
board maxx maxy = empty [(x,y) | x <- [1..maxx], y <- [1..maxy]]

-- create a crosshatch-shaped square board of arbitrary dimension
hatch :: Int -> Board
hatch n = empty [(x,y) | x <- [1..2*n+1], y <- [1..2*n+1], odd y || x == 1 || x == (2*n+1) || odd x]

-- some example Domineering games
board4x4_3 = Board { turn = H,
                     free = [(1,1),(1,2),(2,2),(2,3),(2,4),(3,2),(3,3),(3,4),(4,1),(4,2),(4,3),(4,4)],
                     hist = [(1,3),(2,1)] }

alphaDom_vs_LeeSedom =
  Board { turn = V,
          free = [(-4,1),(-4,3),(-2,0),(-2,4),(2,1),(2,4),(3,-4),(3,4),(4,-2),(4,0)],
          hist = [(0,4),(4,1),(0,-4),(-4,-3),(-1,-2),(2,-1),(-2,-4),(-4,-1),(-1,2),(4,3),(1,2),(-2,2),(-4,-4),(-2,-2),(2,-2),(4,-4),(-3,1),(2,-4),(-4,4),(-1,3),(-4,2),(-3,-2),(3,-1),(1,-3),(-2,-3),(3,1),(1,3)] }

alphaDom_vs_RanDom =
  Board { turn = V,
          free = [(-4,-3),(-4,0),(-2,-4),(-2,-2),(-1,-4),(-1,-2),(-1,2),(-1,4),(0,-4),(0,-2),(0,2),(0,4),(1,-4),(1,-2),(1,2),(1,4),(2,-4),(2,-2),(2,4),(3,-4),(4,0),(4,3)],
          hist = [(-3,4),(2,-1),(-3,2),(4,-2),(-4,-4),(-4,3),(3,4),(2,1),(-3,1),(3,1),(-4,-1),(-2,-1),(-2,3),(-4,1),(1,3),(4,-4),(-4,-2),(4,1),(1,-3),(3,-2),(-2,-3)] }

-- start of Question 1

legalMoves :: Player -> Board -> [Cell]
legalMoves H b = [x | x <- free b, elem (adjCell x H) (free b)]
legalMoves V b = [x | x <- free b, elem (adjCell x V) (free b)]

moveLegal :: Board -> Cell -> Board
moveLegal b c = if c `elem` free b
                then Board {turn = opp (turn b), free = delete (adjCell c (turn b)) (delete c (free b)), hist = c:hist b}
                else error "illegal move"

replay :: Board -> [Board]
replay b = if length (hist b) /= 0
           then replay prevB ++ [b]
           else [b]
           where prevB = Board {turn = opp (turn b), free = (moveCells (turn b) moveCell) ++ (free b), hist = delete moveCell (hist b)}
                 moveCell = head (hist b)
                 moveCells :: Player -> Cell -> [Cell]
                 moveCells H c = [c]++[adjCell c H]
                 moveCells V c = [c]++[adjCell c V]

-- start of Question 2

gametree :: Board -> Tree Board
gametree b = Node b [gametree (moveLegal b c) | c <- legalMoves (turn b) b]

prune :: Int -> Tree a -> Tree a
prune 0 (Node x _)  = Node x []
prune n (Node x ts) = Node x [prune (n-1) t | t <- ts]

score :: Board -> Score
score b = if length (legalMoves (turn b) b) == 0
          then Win (opp (turn b))
          else Heu (length (legalMoves V b) - length (legalMoves H b) - sign (turn b))
          where sign :: Player -> Int
                sign H = -1
                sign V = 1

minimax :: (Board -> Score) -> Tree Board -> Tree (Board, Score)
minimax f (Node b []) = case f b of
                        Win H -> Node (b, Win H) []
                        Win V -> Node (b, Win V) []
                        otherwise -> Node (b, f b) []
minimax f (Node b ts) = case turn b of
                        H -> Node (b, minimum ps) ts'
                        V -> Node (b, maximum ps) ts'
                        where ts' = map (minimax f) (ts)
                              ps = [p | Node (_, p) _ <- ts']

bestmoves :: Int -> (Board -> Score) -> Board -> [Cell]
bestmoves 0 f b = []
bestmoves n f b = [head (hist b') | Node (b', p') _ <- ts, p' == best]
                    where tree = prune n (gametree b)
                          Node (_, best) ts = minimax f tree

chooseSafe :: PickingMonad m => [a] -> m (Maybe a)
chooseSafe [] = return Nothing
chooseSafe xs = do
  i <- pick 0 (length xs - 1)
  return (Just (xs !! i))

randomBestPlay :: PickingMonad m => Int -> (Board -> Score) -> Board -> m (Maybe Cell)
randomBestPlay d sfn = chooseSafe . bestmoves d sfn
randomPlay :: PickingMonad m => Board -> m (Maybe Cell)
randomPlay b = chooseSafe (legalMoves (turn b) b)

-- start of Question 3

runGame :: PickingMonad m => (Board -> m (Maybe Cell)) -> (Board -> m (Maybe Cell)) -> Board -> m Board
runGame playH playV b = if turn b == H
                        then
                            do
                            move <- playH b
                            case move of
                                Nothing -> return b
                                Just n -> runGame playH playV (moveLegal b n)
                        else
                            do
                            move <- playV b
                            case move of
                                Nothing -> return b
                                Just n -> runGame playH playV (moveLegal b n)

-- start of Question 4

carpets :: [Board]
carpets = makeTurn [empty [increment (x,y) | x <- [0..3^n-1], y <- [0..3^n-1], isBlank x y] | n <- [0..]]
            where makeTurn :: [Board] -> [Board]
                  makeTurn [] = []
                  makeTurn (b1:b2:bs) = b1:makeTurn' b2:makeTurn bs
                  makeTurn' :: Board -> Board
                  makeTurn' (Board {turn  = H, free = f, hist = h}) = Board {turn = V,free = f,hist = h}



isBlank :: Int -> Int -> Bool
isBlank 0 _ = True
isBlank _ 0 = True
isBlank x y = not ((xr == 1) && (yr == 1)) && isBlank xq yq
                where ((xq, xr), (yq,yr)) = (x `divMod` 3, y `divMod` 3)

increment :: Cell -> Cell
increment (a,b) = (a+1, b+1)

myStrategy :: PickingMonad m => Board -> m (Maybe Cell)
myStrategy b = undefined
