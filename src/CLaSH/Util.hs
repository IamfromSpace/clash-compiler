{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE TypeSynonymInstances #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module CLaSH.Util
  ( module CLaSH.Util
  , module Control.Applicative
  , module Control.Arrow
  , mkLabels
  )
where

import Control.Applicative              ((<$>),(<*>),pure)
import Control.Arrow                    (first,second)
import Control.Monad.Reader             (Reader,runReader)
import Control.Monad.State              (MonadState,State)
import Control.Monad.Trans.Class        (MonadTrans,lift)
import Data.Hashable                    (Hashable(..))
import Data.HashMap.Lazy                (HashMap)
import qualified Data.HashMap.Lazy   as HashMap
import Data.Label                       ((:->),mkLabels)
import qualified Data.Label.PureM    as LabelM
import Debug.Trace                      (trace)
import qualified Language.Haskell.TH as TH
import Unbound.LocallyNameless          (Embed(..))
import Unbound.LocallyNameless.Name     (Name(..))

class MonadUnique m where
  getUniqueM :: m Int

instance Hashable (Name a) where
  hash (Nm _ (str,int)) = hashWithSalt (hash int) str
  hash (Bn _ i0 i1)     = hash i0 `hashWithSalt` i1

instance (Ord a) => Ord (Embed a) where
  compare (Embed a) (Embed b) = compare a b

curLoc ::
  TH.Q TH.Exp
curLoc = do
  (TH.Loc _ _ modName (startPosL,_) _) <- TH.location
  TH.litE (TH.StringL $ modName ++ "(" ++ show startPosL ++ "): ")

makeCachedM ::
  (MonadState s m, Hashable k, Eq k)
  => k
  -> s :-> (HashMap k (m v))
  -> m v
  -> m v
makeCachedM key lens create = do
  cache <- LabelM.gets lens
  case HashMap.lookup key cache of
    Just create' -> create'
    Nothing -> do
      LabelM.modify lens (HashMap.insert key create)
      create

makeCached ::
  (MonadState s m, Hashable k, Eq k)
  => k
  -> s :-> (HashMap k v)
  -> m v
  -> m v
makeCached key lens create = do
  cache <- LabelM.gets lens
  case HashMap.lookup key cache of
    Just value -> return value
    Nothing -> do
      value <- create
      LabelM.modify lens (HashMap.insert key value)
      return value

makeCachedT3 ::
  ( MonadTrans t2, MonadTrans t1, MonadTrans t
  , Eq k, Hashable k
  , MonadState s m
  , Monad (t2 m), Monad (t1 (t2 m)), Monad (t (t1 (t2 m))))
  => k
  -> s :-> (HashMap k v)
  -> (t (t1 (t2 m))) v
  -> (t (t1 (t2 m))) v
makeCachedT3 key lens create = do
  cache <- (lift . lift . lift) $ LabelM.gets lens
  case HashMap.lookup key cache of
    Just value -> return value
    Nothing -> do
      value <- create
      (lift . lift . lift) $ LabelM.modify lens (HashMap.insert key value)
      return value

secondM ::
  Functor f
  => (b -> f c)
  -> (a, b)
  -> f (a, c)
secondM f (x,y) = fmap ((,) x) (f y)

firstM ::
  Functor f
  => (a -> f c)
  -> (a, b)
  -> f (c, b)
firstM f (x,y) = fmap (flip (,) $ y) (f x)

traceIf :: Bool -> String -> a -> a
traceIf True  msg = trace msg
traceIf False _   = id

partitionM ::
  (Monad m)
  => (a -> m Bool)
  -> [a]
  -> m ([a], [a])
partitionM _ []     = return ([], [])
partitionM p (x:xs) = do
  test      <- p x
  (ys, ys') <- partitionM p xs
  return $ if test then (x:ys, ys') else (ys, x:ys')

mapAccumLM ::
  (Monad m)
  => (acc -> x -> m (acc,y))
  -> acc
  -> [x]
  -> m (acc,[y])
mapAccumLM _ acc [] = return (acc,[])
mapAccumLM f acc (x:xs) = do
  (acc',y) <- f acc x
  (acc'',ys) <- mapAccumLM f acc' xs
  return (acc'',y:ys)

dot :: (b -> c) -> (a0 -> a1 -> b) -> a0 -> a1 -> c
dot = (.) . (.)

localReader ::
  s1 :-> s2
  -> Reader s2 a
  -> State s1 a
localReader lens reader = do
  s <- LabelM.gets lens
  return $ runReader reader s
