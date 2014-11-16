module Database.Postgres where

import Control.Monad.Eff
import Control.Monad.Cont.Trans
import Control.Monad.Trans
import Data.Either
import Data.Array
import Data.Foreign
import Data.Foreign.Class

type Query = String

foreign import data Client :: *

foreign import data DB :: !

type DBEff eff = Eff (db :: DB | eff)

type ConnectionInfo =
  { host :: String
  , db :: String
  , port :: Number
  , user :: String
  , password :: String
  }


-- Low-level API. --------------------------------------------------------------

connect :: forall eff. ConnectionInfo -> DBEff eff Client
connect ci = connectJS $ "postgres://" <> ci.user <> ":" <> ci.password <> "@" <> ci.host <> ":" <> show ci.port <> "/" <> ci.db

runQuery :: forall row eff. (IsForeign row) =>
            Query -> Client -> ([F row] -> DBEff eff Unit) -> DBEff eff Unit
runQuery query client handleRows = runQueryRowsForeignRaw query client (map read >>> handleRows)


foreign import connectJS """
  function connectJS(conString) {
    return function() {
      var pg = require('pg');
      var client = new pg.Client(conString);
      return client;
    };
  }
""" :: forall eff. String -> DBEff eff Client


foreign import connectClient """
  function connectClient(client) {
    return function() {
      client.connect();
    };
  }
""" :: forall eff. Client -> DBEff eff Unit

foreign import endClient """
  function endClient(client) {
    return function() {
      client.end();
    };
  }
""" :: forall eff. Client -> DBEff eff Unit


foreign import runQueryRowsForeignRaw """
  function runQueryRowsForeignRaw(queryStr) {
      return function (client) {
        return function(handleRows) {
            return function() {
              client.query(queryStr, function(err, result) {
                if (err) {
                  console.error('error running query', err);
                } else {
                  handleRows(result.rows)();
                }
              });
            };
          };
        };
  }
  """ :: forall eff eff'. Query -> Client -> ([Foreign] -> eff') -> DBEff eff Unit


-- Continuation-based API. -----------------------------------------------------

runQueryCont :: forall eff a. (IsForeign a) => Query -> Client -> ContT Unit (DBEff eff) [F a]
runQueryCont query client = ContT $ runQuery query client

withConnectionCont :: forall eff a. ConnectionInfo -> (Client -> ContT Unit (DBEff eff) a) -> ContT Unit (DBEff eff) a
withConnectionCont connectionInfo dbProg = do
  client <- lift $ connect connectionInfo
  lift $ connectClient client
  res <- dbProg client
  lift $ endClient client
  return res
