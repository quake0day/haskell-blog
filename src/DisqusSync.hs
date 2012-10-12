{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.List (intersperse)
import Data.Map ((!))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time
import Database.HDBC
import Database.HDBC.MySQL
import Network.Curl
import System.Locale
import Text.JSON

import Config


data DisqusResponse
  = ServiceError String
  | JSONResult JSValue
    deriving (Show)

data DisqusComment = DisqusComment
  { dcIsJuliaFlagged :: Bool
  , dcIsFlagged :: Bool
  , dcParent :: Maybe Int
  -- , dcAuthor :: DisqusAuthor
  -- , dcMedia :: [DisqusMedia]
  , dcIsDeleted :: Bool
  , dcIsApproved :: Bool
  , dcDislikes :: Int
  , dcRawMessage :: Text
  , dcCreatedAt :: Text -- DateTime
  , dcId :: Text -- Int ????
  , dcThread :: Text
  , dcNumReports :: Int
  , dcIsEdited :: Bool
  , dcLikes :: Int
  , dcPoints :: Int
  , dcMessage :: Text
  , dcIsSpam :: Bool
  , dcIsHighlighted :: Bool
  , dcUserScore :: Int
  , dcMyThread :: Maybe Int
  } deriving (Show)

instance JSON DisqusComment where
  showJSON _ = JSNull

  readJSON (JSObject a@obj)
    | isError getIsJuliaFlagged = toError "isJuliaFlagged not found" getIsJuliaFlagged
    | isError getIsFlagged = toError "isFlagged not found" getIsFlagged
    | isError getParent = toError "parent not found" getParent
    | isError getIsDeleted = toError "isDeleted not found" getIsDeleted
    | isError getIsApproved = toError "isApproved not found" getIsApproved
    | isError getDislikes = toError "dislikes not found" getDislikes
    | isError getRawMessage = toError "raw_message not found" getRawMessage
    | isError getCreatedAt = toError "createdAt not found" getCreatedAt
    | isError getId = toError "id not found" getId
    | isError getThread = toError "thread not found" getThread
    | isError getNumReports = toError "numReports not found" getNumReports
    | isError getIsEdited = toError "isEdited not found" getIsEdited
    | isError getLikes = toError "likes not found" getLikes
    | isError getPoints = toError "points not found" getPoints
    | isError getMessage = toError "message not found" getMessage
    | isError getIsSpam = toError "isSpam not found" getIsSpam
    | isError getIsHighlighted = toError "isHighlighted not found" getIsHighlighted
    | isError getUserScore = toError "userScore not found" getUserScore
    | otherwise = Ok $ DisqusComment
      { dcIsJuliaFlagged = fromResult getIsJuliaFlagged
      , dcIsFlagged = fromResult getIsFlagged
      , dcParent =
        case fromResult getParent of
          JSRational _ b -> Just $ round $ fromRational b
          _ -> Nothing
      -- , dcAuthor :: DisqusAuthor
      -- , dcMedia :: [DisqusMedia]
      , dcIsDeleted = fromResult getIsDeleted
      , dcIsApproved = fromResult getIsApproved
      , dcDislikes = fromResult getDislikes
      , dcRawMessage = T.pack $ fromResult getRawMessage
      , dcCreatedAt = T.pack $ fromResult getCreatedAt  -- DateTime
      , dcId = T.pack $ fromResult getId
      , dcThread = T.pack $ fromResult getThread
      , dcNumReports = fromResult getNumReports
      , dcIsEdited = fromResult getIsEdited
      , dcLikes = fromResult getLikes
      , dcPoints = fromResult getPoints
      , dcMessage = T.pack $ fromResult getMessage
      , dcIsSpam = fromResult getIsSpam
      , dcIsHighlighted = fromResult getIsHighlighted
      , dcUserScore = fromResult getUserScore
      , dcMyThread = Nothing
      }
    where
      getIsJuliaFlagged = valFromObj "isJuliaFlagged" obj
      getIsFlagged = valFromObj "isFlagged" obj
      getParent = valFromObj "parent" obj
      getIsDeleted = valFromObj "isDeleted" obj
      getIsApproved = valFromObj "isApproved" obj
      getDislikes = valFromObj "dislikes" obj
      getRawMessage = valFromObj "raw_message" obj
      getCreatedAt = valFromObj "createdAt" obj
      getId = valFromObj "id" obj
      getThread = valFromObj "thread" obj
      getNumReports = valFromObj "numReports" obj
      getIsEdited = valFromObj "isEdited" obj
      getLikes = valFromObj "likes" obj
      getPoints = valFromObj "points" obj
      getMessage = valFromObj "message" obj
      getIsSpam = valFromObj "isSpam" obj
      getIsHighlighted = valFromObj "isHighlighted" obj
      getUserScore = valFromObj "userScore" obj
  readJSON _ = Error "Error in discus comment"

isError (Ok _) = False
isError (Error _) = True

fromResult (Ok a) = a
fromResult (Error str) = error $ "Decode error: " ++ str

toError :: String -> Result a -> Result b
toError prefix (Error str) = Error $ prefix ++ ": " ++ str
toError prefix _ = Error $ prefix ++ ": Access error"

disqusApiKey :: String
disqusApiKey = "eEu5UUONIskKunn9HIudZ8DUpAdPPkbgwsLBzyeVRD4ACEqtOqY1OPdC2cfL7CJ2"

curlDo :: String -> IO (String)
curlDo url = withCurlDo $ do
  h <- initialize
  response <- curl h (url) []
  return $ respBody response
  where
    curl :: Curl -> URLString -> [CurlOption] -> IO CurlResponse
    curl = do_curl_


listPosts :: LocalTime -> IO ([DisqusComment], [String]) -- Comments, error messages
listPosts since = do
  postsString <- curlDo url
  let res = decode postsString
  case filterError res of
    (Ok (JSArray arr)) -> return $ transformArray arr
    (Ok other) -> return ([], ["Server should return array but return " ++ encode other])
    (Error str) -> return ([], [str])
  where
    url = "https://disqus.com/api/3.0/forums/listPosts.json?forum=dikmax&api_key=" ++ disqusApiKey ++
      "&order=asc&since=" ++ (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S" since)
    transformArray :: [JSValue] -> ([DisqusComment], [String])
    transformArray [] = ([], [])
    transformArray (x:xs) =
      case parseItem x of
        (Ok item) -> (item : (fst $ transformArray xs), snd $ transformArray xs)
        (Error str) -> (fst $ transformArray xs, str : (snd $ transformArray xs))
    parseItem item = readJSON item


filterError :: Result JSValue -> Result JSValue
filterError res@(Ok (JSObject obj))
  | getCode obj == Just 0 = valFromObj "response" obj
  | (maybe 0 id $ getCode obj) > 0 =
    case (valFromObj "response" obj :: Result JSValue) of
      (Ok (JSString str)) -> Error $ fromJSString str
      _ -> Error "Error with no message"
  | otherwise = Error $ show res
  where
    getCode obj = getCode_ $ valFromObj "code" obj
    getCode_ (Ok (JSRational False a)) = Just a
    getCode_ _ = Nothing

filterError (Ok a) = Error $ "Server should return object but returned: " ++ show a
filterError e = e

processResponse (Ok a) = JSONResult a
processResponse (Error e) = ServiceError e

-- Database functions
getSince :: (IConnection a) => a -> IO (LocalTime)
getSince conn = do
  stmt <- prepare conn "SELECT MAX(date) FROM posts"
  executeRaw stmt
  res <- fetchRow stmt
  finish stmt
  case res of
    Just [SqlNull] -> return $ LocalTime (fromGregorian 2012 3 1) midnight
    Just [v] -> return $ fromSql v
    _ -> return $ LocalTime (fromGregorian 2012 3 1) midnight

getKnownThreads :: (IConnection a) => a -> [DisqusComment] -> IO ([DisqusComment])
getKnownThreads _ [] = return []
getKnownThreads conn comments = do
  stmt <- prepare conn ("SELECT id, disqus_thread " ++
    "FROM posts " ++
    "WHERE disqus_thread IN (" ++
    (intersperse ',' $ map (\_ -> '?') comments) ++ ")")
  execute stmt $ map (toSql . dcThread) comments
  updateData stmt comments
  where
    updateData stmt comments = do
      row <- fetchRowMap stmt
      case row of
        Just rw -> updateData stmt $
          map (updateComment (fromSql $ rw ! "id") (fromSql $ rw ! "disqus_thread")) comments
        Nothing -> return comments

    updateComment pId disqusThread comment
      | dcThread comment == disqusThread = comment
        { dcMyThread = Just pId }
      | otherwise = comment

main :: IO ()
main = do
  conn <- connectMySQL connectInfo
  since <- getSince conn
  (posts, errors) <- listPosts since
  updatedPosts <- getKnownThreads conn posts
  putStrLn $ show $ map (\a -> (dcThread a, dcMyThread a)) updatedPosts
  writeErrors errors
  --  case posts of
  --    (Ok a) -> putStrLn $ show a
  --    (Error _) -> putStrLn $ show posts
  disconnect conn
  where
    writeErrors [] = return ()
    writeErrors (e:es) = do
      putStrLn e
      writeErrors es
