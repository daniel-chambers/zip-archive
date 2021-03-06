{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE CPP #-}
-- Test suite for Codec.Archive.Zip
-- runghc Test.hs

import Codec.Archive.Zip
import System.Directory
import Test.HUnit.Base
import Test.HUnit.Text
import System.Process
import qualified Data.ByteString.Lazy as B
import Control.Applicative
import System.Exit
import System.IO.Temp (withTempDirectory)

#ifndef _WINDOWS
import System.Posix.Files
#endif

-- define equality for Archives so timestamps aren't distinguished if they
-- correspond to the same MSDOS datetime.
instance Eq Archive where
  (==) a1 a2 =  zSignature a1 == zSignature a2
             && zComment a1 == zComment a2
             && (all id $ zipWith (\x y -> x { eLastModified = eLastModified x `div` 2  } ==
                                           y { eLastModified = eLastModified y `div` 2  }) (zEntries a1) (zEntries a2))

main :: IO Counts
main = withTempDirectory "." "test-zip-archive." $ \tmpDir -> do
  res   <- runTestTT $ TestList $ map (\f -> f tmpDir)
                                [ testReadWriteArchive
                                , testReadExternalZip
                                , testFromToArchive
                                , testReadWriteEntry
                                , testAddFilesOptions
                                , testDeleteEntries
                                , testExtractFiles
#ifndef _WINDOWS
                                , testExtractFilesWithPosixAttrs
#endif
                                ]
  exitWith $ case (failures res + errors res) of
                     0 -> ExitSuccess
                     n -> ExitFailure n

testReadWriteArchive :: FilePath -> Test
testReadWriteArchive tmpDir = TestCase $ do
  archive <- addFilesToArchive [OptRecursive] emptyArchive ["LICENSE", "src"]
  B.writeFile (tmpDir ++ "/test1.zip") $ fromArchive archive
  archive' <- toArchive <$> B.readFile (tmpDir ++ "/test1.zip")
  assertEqual "for writing and reading test1.zip" archive archive'
  assertEqual "for writing and reading test1.zip" archive archive'

testReadExternalZip :: FilePath -> Test
testReadExternalZip tmpDir = TestCase $ do
  _ <- runCommand ("zip -q " ++ tmpDir ++
           "/test4.zip zip-archive.cabal src/Codec/Archive/Zip.hs") >>=
           waitForProcess
  archive <- toArchive <$> B.readFile (tmpDir ++ "/test4.zip")
  let files = filesInArchive archive
  assertEqual "for results of filesInArchive" ["zip-archive.cabal", "src/Codec/Archive/Zip.hs"] files
  cabalContents <- B.readFile "zip-archive.cabal"
  case findEntryByPath "zip-archive.cabal" archive of 
       Nothing  -> assertFailure "zip-archive.cabal not found in archive"
       Just f   -> assertEqual "for contents of zip-archive.cabal in archive" cabalContents (fromEntry f)

testFromToArchive :: FilePath -> Test
testFromToArchive _tmpDir = TestCase $ do
  archive <- addFilesToArchive [OptRecursive] emptyArchive ["LICENSE", "src"]
  assertEqual "for (toArchive $ fromArchive archive)" archive (toArchive $ fromArchive archive)

testReadWriteEntry :: FilePath -> Test
testReadWriteEntry tmpDir = TestCase $ do
  entry <- readEntry [] "zip-archive.cabal"
  setCurrentDirectory tmpDir
  writeEntry [] entry
  setCurrentDirectory ".."
  entry' <- readEntry [] (tmpDir ++ "/zip-archive.cabal")
  let entry'' = entry' { eRelativePath = eRelativePath entry, eLastModified = eLastModified entry }
  assertEqual "for readEntry -> writeEntry -> readEntry" entry entry''

testAddFilesOptions :: FilePath -> Test
testAddFilesOptions _tmpDir = TestCase $ do
  archive1 <- addFilesToArchive [OptVerbose] emptyArchive ["LICENSE", "src"]
  archive2 <- addFilesToArchive [OptRecursive, OptVerbose] archive1 ["LICENSE", "src"]
  assertBool "for recursive and nonrecursive addFilesToArchive"
     (length (filesInArchive archive1) < length (filesInArchive archive2))

testDeleteEntries :: FilePath -> Test
testDeleteEntries _tmpDir = TestCase $ do
  archive1 <- addFilesToArchive [] emptyArchive ["LICENSE", "src"]
  let archive2 = deleteEntryFromArchive "LICENSE" archive1
  let archive3 = deleteEntryFromArchive "src" archive2
  assertEqual "for deleteFilesFromArchive" emptyArchive archive3

testExtractFiles :: FilePath -> Test
testExtractFiles tmpDir = TestCase $ do
  createDirectory (tmpDir ++ "/dir1")
  createDirectory (tmpDir ++ "/dir1/dir2")
  let hiMsg = "hello there"
  let helloMsg = "Hello there. This file is very long.  Longer than 31 characters."
  writeFile (tmpDir ++ "/dir1/hi") hiMsg
  writeFile (tmpDir ++ "/dir1/dir2/hello") helloMsg
  archive <- addFilesToArchive [OptRecursive] emptyArchive [(tmpDir ++ "/dir1")]
  removeDirectoryRecursive (tmpDir ++ "/dir1")
  extractFilesFromArchive [OptVerbose] archive
  hi <- readFile (tmpDir ++ "/dir1/hi")
  hello <- readFile (tmpDir ++ "/dir1/dir2/hello")
  assertEqual ("contents of " ++ tmpDir ++ "/dir1/hi") hiMsg hi
  assertEqual ("contents of " ++ tmpDir ++ "/dir1/dir2/hello") helloMsg hello

#ifndef _WINDOWS
testExtractFilesWithPosixAttrs :: FilePath -> Test
testExtractFilesWithPosixAttrs tmpDir = TestCase $ do
  createDirectory (tmpDir ++ "/dir3")
  let hiMsg = "hello there"
  writeFile (tmpDir ++ "/dir3/hi") hiMsg
  let perms = unionFileModes ownerReadMode $ unionFileModes ownerWriteMode ownerExecuteMode
  setFileMode (tmpDir ++ "/dir3/hi") perms
  archive <- addFilesToArchive [OptRecursive] emptyArchive [(tmpDir ++ "/dir3")]
  removeDirectoryRecursive (tmpDir ++ "/dir3")
  extractFilesFromArchive [OptVerbose] archive
  hi <- readFile (tmpDir ++ "/dir3/hi")
  fm <- fmap fileMode $ getFileStatus (tmpDir ++ "/dir3/hi")
  assertEqual "file modes" perms (intersectFileModes perms fm)
  assertEqual ("contents of " ++ tmpDir ++ "/dir3/hi") hiMsg hi
#endif
