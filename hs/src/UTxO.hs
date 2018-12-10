{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell   #-}

{-|
Module      : UTxO
Description : Simple UTxO Ledger

This module defines the types and functions for a simple UTxO Ledger
as specified in /A Simplified Formal Specification of a UTxO Ledger/.
-}

module UTxO
  (
  -- * Primitives
    TxId(..)
  , Addr(..)
  -- * Derived Types
  , TxIn(..)
  , TxOut(..)
  , UTxO(..)
  , Tx(..)
  -- * Functions
  , txid
  , txins
  , txouts
  , balance
  , depositAmount
  , (<|)
  , (</|)
  , dom
  -- , verify
  , union
  , makeWitness
  , Wit(..)
  , TxWits(..)
  ) where

import           Crypto.Hash             (Digest, SHA256, hash)
import qualified Data.ByteArray          as BA
import qualified Data.ByteString.Char8   as BS
import           Data.Map                (Map)
import qualified Data.Map                as Map
import           Data.Set                (Set)
import qualified Data.Set                as Set
import           Numeric.Natural         (Natural)

import Lens.Micro ((^.), (&), (.~), (+~), (-~))
import Lens.Micro.TH (makeLenses)

import           Coin                    (Coin (..))
import           Keys
import           PrtlConsts (PrtlConsts(..))
import           Slot (Slot(..))

import           Delegation.Certificates (DCert (..), dvalue)
import           Delegation.StakePool (StakePool (..), poolPubKey)

-- |A hash
type Hash = Digest SHA256

-- |A unique ID of a transaction, which is computable from the transaction.
newtype TxId = TxId { _TxId :: Hash }
  deriving (Show, Eq, Ord)

-- |An address for UTxO.
data Addr = AddrTxin HashKey HashKey
          deriving (Show, Eq, Ord)

-- |The input of a UTxO.
data TxIn = TxIn TxId Natural deriving (Show, Eq, Ord)

-- |The output of a UTxO.
data TxOut = TxOut Addr Coin deriving (Show, Eq, Ord)

-- |The unspent transaction outputs.
newtype UTxO = UTxO (Map TxIn TxOut) deriving (Show, Eq, Ord)

-- |A raw transaction
data Tx = Tx { _inputs  :: !(Set TxIn)
             , _outputs :: [TxOut]
             , _certs   :: ![DCert]
             , _txfee   :: Coin
             , _ttl     :: Slot
             } deriving (Show, Eq, Ord)

makeLenses ''Tx

-- |Compute the id of a transaction.
txid :: Tx -> TxId
txid = TxId . hash

-- |Compute the UTxO inputs of a transaction.
txins :: Tx -> Set TxIn
txins = flip (^.) inputs

-- |Compute the transaction outputs of a transaction.
txouts :: Tx -> UTxO
txouts tx = UTxO $
  Map.fromList [(TxIn transId idx, out) | (out, idx) <- zip (tx ^. outputs) [0..]]
  where
    transId = txid tx

-- |Proof/Witness that a transaction is authorized by the given key holder.
data Wit = Wit VKey !(Sig Tx) deriving (Show, Eq, Ord)

-- |A fully formed transaction.
--
--     * __TODO__ - Would it be better to name this type Tx, and rename Tx to TxBody?
data TxWits = TxWits
              { _body       :: !Tx
              , _witnessSet :: !(Set Wit)
              } deriving (Show, Eq, Ord)

-- |Create a witness for transaction
makeWitness :: KeyPair -> Tx -> Wit
makeWitness keys tx = Wit (vKey keys) (sign (sKey keys) tx)

-- |Domain restriction
(<|) :: Set TxIn -> UTxO -> UTxO
ins <| (UTxO utxo) =
  UTxO $ Map.filterWithKey (\k _ -> k `Set.member` ins) utxo

-- |Domain exclusion
(</|) :: Set TxIn -> UTxO -> UTxO
ins </| (UTxO utxo) =
  UTxO $ Map.filterWithKey (\k _ -> k `Set.notMember` ins) utxo

-- | Domain of UTxO
dom :: UTxO -> Set TxIn
dom (UTxO utxo) = Map.keysSet utxo

-- |Combine two collections of UTxO.
--
--     * TODO - Should we return 'Maybe UTxO' so that we can return
-- Nothing when the collections are not disjoint?
union :: UTxO -> UTxO -> UTxO
union (UTxO a) (UTxO b) = UTxO $ Map.union a b

-- |Determine the total balance contained in the UTxO.
balance :: UTxO -> Coin
balance (UTxO utxo) = foldr addCoins mempty utxo
  where addCoins (TxOut _ a) b = a <> b

-- |Determine the total deposit amount needed
depositAmount :: PrtlConsts -> Map.Map HashKey Slot -> Tx -> Coin
depositAmount pc stpools tx = foldl f (Coin 0) cs
  where
    f coin cert = coin + dvalue cert pc
    notRegisteredPool (RegPool pool) = Map.notMember (hashKey $ pool ^. poolPubKey) stpools
    notRegisteredPool _ = True
    cs = filter notRegisteredPool (tx ^. certs)

instance BA.ByteArrayAccess Tx where
  length        = BA.length . BS.pack . show
  withByteArray = BA.withByteArray . BS.pack  . show
