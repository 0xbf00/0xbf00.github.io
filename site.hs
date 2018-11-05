{-# LANGUAGE OverloadedStrings #-}

import Data.Monoid
import Hakyll

-- | Util
-------------------------------------------------------------------------------

postCtx :: Context String
postCtx = 
    dateField "date" "%B %e, %Y" `mappend` 
    defaultContext

-- | Deploy
-------------------------------------------------------------------------------

deployCmd :: String
deployCmd = "rsync -a ~/Programming/ubrigens.com-source/_site/ ubrigens:/var/www/ubrigens.com/public_html; ssh ubrigens 'chown -R www-data:www-data /var/www/ubrigens.com/public_html/'"

config :: Configuration
config = defaultConfiguration { deployCommand = deployCmd }

-- | Main
-------------------------------------------------------------------------------
processCompiled :: (Monad m) => Item String -> m (Item String)
processCompiled (Item id body) = return (Item id $ "Hello " ++ show body)

main :: IO ()
main = hakyllWith config $ do

    match "assets/images/*" $ do
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
            >>= loadAndApplyTemplate "templates/default.html" postCtx
            >>= relativizeUrls


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
