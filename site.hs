{-# LANGUAGE OverloadedStrings #-}

import Data.Monoid
import Hakyll
import Data.Text (pack, unpack, replace, empty)
import Data.List (isPrefixOf)

-- | Util
-------------------------------------------------------------------------------

postCtx :: Context String
postCtx = 
    dateField "date" "%B %e, %Y" `mappend` 
    defaultContext

-- | Deploy
-------------------------------------------------------------------------------

-- The following four functions were copied over from
-- https://github.com/divarvel/blog/blob/master/Main.hs#L31-L33
externalizeUrls :: String -> Item String -> Compiler (Item String)
externalizeUrls root item = return $ fmap (externalizeUrlsWith root) item

externalizeUrlsWith :: String -- ^ Path to the site root
                    -> String -- ^ HTML to externalize
                    -> String -- ^ Resulting HTML
externalizeUrlsWith root = withUrls ext
  where
    ext x = if isExternal x then x else root ++ x

-- TODO: clean me
unExternalizeUrls :: String -> Item String -> Compiler (Item String)
unExternalizeUrls root item = return $ fmap (unExternalizeUrlsWith root) item

unExternalizeUrlsWith :: String -- ^ Path to the site root
                      -> String -- ^ HTML to unExternalize
                      -> String -- ^ Resulting HTML
unExternalizeUrlsWith root = withUrls unExt
  where
    unExt x = if root `isPrefixOf` x then unpack $ replace (pack root) empty (pack x) else x


deployCmd :: String
deployCmd = "./deploy.sh"

config :: Configuration
config = defaultConfiguration { deployCommand = deployCmd }

-- | Main
-------------------------------------------------------------------------------
processCompiled :: (Monad m) => Item String -> m (Item String)
processCompiled (Item id body) = return (Item id $ "Hello " ++ show body)

ubrigensFeedConfig :: FeedConfiguration
ubrigensFeedConfig = FeedConfiguration
    { feedTitle = "Ubrigens"
    , feedDescription = "Personal blog about reverse engineering and IT security"
    , feedAuthorName = "Jakob Rieck"
    , feedAuthorEmail = "jakobrieck+blog@gmail.com"
    , feedRoot = "https://ubrigens.com"
    }

main :: IO ()
main = hakyllWith config $ do
    match "assets/images/**" $ do
        route   idRoute
        compile copyFileCompiler

    match "assets/css/*" $ do
        route   idRoute
        compile compressCssCompiler

    match "assets/js/*.js" $ do
        route   idRoute
        compile copyFileCompiler

    match "assets/js/*.coffee" $ do
        route   $ setExtension "js"
        compile $ getResourceString 
            >>= withItemBody (unixFilter "coffee" ["-c", "-s"])

    match "about.markdown" $ do
        route   $ setExtension "html"
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/default.html" defaultContext
            >>= relativizeUrls

    match "posts/*" $ do
        route $ setExtension "html"

        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/post.html"    postCtx
            >>= externalizeUrls (feedRoot ubrigensFeedConfig)
            >>= saveSnapshot "content" -- Template saved for Atom feed
            >>= unExternalizeUrls (feedRoot ubrigensFeedConfig)
            >>= loadAndApplyTemplate "templates/default.html" postCtx
            >>= relativizeUrls

    create ["atom.xml"] $ do
        route idRoute
        compile $ do
            let feedCtx = postCtx `mappend`
                    bodyField "description"

            posts <- fmap (take 25) . recentFirst =<< loadAllSnapshots "posts/*" "content"
            renderAtom ubrigensFeedConfig feedCtx posts

    match "index.html" $ do
        route idRoute
        compile $ do
            posts <- recentFirst =<< loadAll "posts/*"
            let indexCtx =
                    listField "posts" postCtx (return posts) `mappend`
                    constField "title" "Home"                `mappend`
                    defaultContext

            getResourceBody
                >>= applyAsTemplate indexCtx
                >>= loadAndApplyTemplate "templates/default.html" indexCtx
                >>= relativizeUrls

    match "templates/*" $ compile templateCompiler

    match ("CNAME" .||. "keybase.txt") $ do
        route   idRoute
        compile copyFileCompiler