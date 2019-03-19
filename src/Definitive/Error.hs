{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveFunctor      #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE GADTs              #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE PolyKinds          #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeOperators      #-}
{-# LANGUAGE UnicodeSyntax      #-}

module Definitive.Error
  ( Error (..)
  , throw
  , catch
  , runError
  ) where

import qualified Control.Monad.Trans.Except as E
import           Definitive
import           Definitive.Effect


data Error e m a
  = Throw e
  | ∀ x. Catch (m x) (e -> m x) (x -> a)

deriving instance Functor (Error e m)

instance Effect (Error e) where
  weave _ _ (Throw e) = Throw e
  weave s f (Catch try handle k) =
    Catch (f $ try <$ s) (\e -> f $ handle e <$ s) $ fmap k
  {-# INLINE weave #-}

  hoist f (Catch try handle k) =
    Catch (f try) (fmap f handle) k
  {-# INLINE hoist #-}


throw :: Member (Error e) r => e -> Def r a
throw = send . Throw


catch :: Member (Error e) r => Def r a -> (e -> Def r a) -> Def r a
catch try handle = send $ Catch try handle id


runError :: Def (Error e ': r) a -> Def r (Either e a)
runError (Freer m) = Freer $ \k -> E.runExceptT $ m $ \u ->
  case decomp u of
    Left x -> E.ExceptT $ k $
      weave (Right ()) (either (pure . Left) runError') x
    Right (Throw e) -> E.throwE e
    Right (Catch try handle kt) -> E.ExceptT $ do
      let runIt = usingFreer k . runError'
      ma <- runIt try
      case ma of
        Right a -> pure . Right $ kt a
        Left e -> do
          ma' <- runIt $ handle e
          case ma' of
            Left e' -> pure $ Left e'
            Right a -> pure . Right $ kt a
{-# INLINE runError #-}


runError' :: Def (Error e ': r) a -> Def r (Either e a)
runError' = runError
{-# NOINLINE runError' #-}

