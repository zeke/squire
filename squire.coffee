##
## squire.coffee
## 
## The entry point into our library when including via require. It's mostly useful for the base
## plugin class to be extended by any actual plugins.
##

lib =
	fs:     require "fs"
	path:   require "path"
	colors: require "colors"
	cson:   require "cson"
	merge:  require "deepmerge"


# This class provides some base functionality that's used throughout the project. It is extended by
# SquirePlugin as well as each command in our command-line utility.
class exports.Squire
	baseConfigDefaults:
		global:
			appDirectory:      "app"
			inputDirectory:    "content"
			outputDirectory:   "build"
			ignoreHiddenFiles: true
			plugins:           []
		preview:
			minify:      false
			enableProxy: false
			proxyHost:   "localhost"
			proxyPort:   80
		build:
			minify: true
	
	constructor: (options = {}) ->
		@mode = options.mode or "build"
		
		# Gather up config values.
		@projectPath   = process.env.PWD
		userConfigPath = "#{@projectPath}/config/squire.cson"
		userConfig     = if lib.fs.existsSync userConfigPath then lib.cson.parseFileSync(userConfigPath) or {} else {}
		userConfig     = lib.merge userConfig.global or {}, userConfig[@mode] or {}
		@config        = lib.merge @baseConfigDefaults.global, @baseConfigDefaults[@mode] or {}
		@config        = lib.merge @config, userConfig
		
		# Store some useful paths.
		@squirePath = __dirname
		@appPath    = "#{@projectPath}/#{@config.appDirectory.trim()}"
		@inputPath  = "#{@appPath}/#{@config.inputDirectory.trim()}"
		@outputPath = "#{@projectPath}/#{@config.outputDirectory.trim()}"
	
	# Takes in a plugin ID and returns a new instance of that plugin, or null if the plugin doesn't
	# exist or can't be loaded.
	loadPlugin: (pluginId) ->
		pluginModule = null
		
		paths = [
			"#{@projectPath}/plugins/#{pluginId}.coffee"
			"#{@squirePath}/plugins/#{pluginId}.coffee"
			"#{@projectPath}/node_modules/squire-#{pluginId}"
		]
		
		# Look for the module in several different places.
		for path in paths
			# If there's something at this path let's try to load it. Hopefully it's a plugin.
			if lib.fs.existsSync path
				pluginModule = require path
				break
		
		if pluginModule?
			plugin     = new pluginModule.Plugin id: pluginId, mode: @mode
			plugin.app = @app
			plugin
		else
			null
	
	# A helper function that will load a file at the given URL and return the contents. It will
	# accept both absolute URLs and URLs relative to a particular base path.
	loadFile: (url, basePath = @appPath) ->
		url = lib.path.join basePath, url if url[0] isnt "/"
		
		if lib.fs.existsSync url
			lib.fs.readFileSync url
		else
			null
	
	# The same as above, but will automatically convert the loaded file to a string. This is useful
	# if you know that the file you're loading is a text file and not binary like an image.
	loadTextFile: (url, basePath = @appPath) ->
		@loadFile(url, basePath).toString()
	
	# Creates a nicely formatted error message and returns it. Plugins use this to create an error
	# that they bubble up to the build process.
	createError: (message, details, url) ->
		fancyMessage = lib.colors.red "\u2718 #{message}"
		error        = "\n#{message}"
		fancyError   = "\n#{fancyMessage}"
		
		if details?
			details    = "\n#{details}"
			details    = "\nIn #{url}:\n#{details}" if url?
			details    = details.replace /\n/g, "\n    "
			error      += "\n#{details}"
			fancyError += "\n#{details}"
		else if url?
			error      += " in #{url}"
			fancyError += " in #{url}"
		
		error      += "\n"
		fancyError += "\n"
		
		{ plainMessage: error, fancyMessage: fancyError }
	
	# A convenience function for logging an error created by the above function.
	logError: (message, details, url) ->
		console.log @createError(message, details, url).fancyMessage
	
	# Takes in a list of error objects (generated by createError) and joins them into a single
	# string based on the error type you're interested ("fancy" or "plain").
	consolidateErrors: (errors, type = "fancy") ->
		(error["#{type}Message"] for error in errors).join "\n\n"
	
	# A little helper function to gather up a bunch of useful information about a url.
	getUrlInfo: (url, basePath = @appPath) ->
		url                    = "#{basePath}/#{url}" unless url[0] is "/"
		url                    = url[0..url.length - 2] if url[url.length - 1] is "/"
		exists                 = lib.fs.existsSync url
		isDirectory            = if exists then lib.fs.lstatSync(url).isDirectory() else url.lastIndexOf("/") > url.lastIndexOf(".")
		path                   = if isDirectory then url else lib.path.dirname url
		pathComponents         = path.split("/")[1..]
		relativePath           = path[basePath.length + 1..]
		relativePathComponents = relativePath.split "/"
		
		if isDirectory
			url:                    url
			baseName:               lib.path.basename url
			components:             pathComponents
			relativePath:           relativePath
			relativePathComponents: relativePathComponents
			isDirectory:            true
		else
			fileName  = lib.path.basename url
			extension = lib.path.extname(fileName)[1..]
			
			url:                    url
			fileName:               fileName
			baseName:               fileName[0...fileName.length - extension.length - 1]
			path:                   path
			extension:              extension
			fileNameComponents:     fileName.split "."
			pathComponents:         pathComponents
			relativePath:           relativePath
			relativeUrl:            if relativePath then "#{relativePath}/#{fileName}" else fileName
			relativePathComponents: relativePathComponents
			isDirectory:            false


# The base plugin class, to be extended by actual plugins.
class exports.SquirePlugin extends exports.Squire
	configDefaults: {}
	fileType:       "text"
	
	constructor: (options = {}) ->
		super
		@id = options.id
		
		# We add to the base config with our plugin-specific config.
		userConfigPath = "#{@projectPath}/config/#{@id}.cson"
		userConfig     = if lib.fs.existsSync userConfigPath then lib.cson.parseFileSync(userConfigPath) or {} else {}
		pluginConfig   = lib.merge { global: {}, preview: {}, build: {} }, @configDefaults
		pluginConfig   = lib.merge pluginConfig, userConfig
		pluginConfig   = lib.merge pluginConfig.global, pluginConfig[@mode] or {}
		@config        = lib.merge @config, pluginConfig
	
	renderContent: (input, options, callback) ->
		callback input
	
	renderContentList: (inputs, options, callback) ->
		results   = []
		allErrors = []
		
		recursiveRender = (index) =>
			input = inputs[index].toString()
			url   = options.urls?[index]
			
			@renderContent input, (if url? then { url: url } else {}), (output, data, errors) ->
				if errors?
					allErrors = allErrors.concat errors
				else
					results.push output
				
				if ++index < inputs.length
					recursiveRender index
				else if allErrors.length > 0
					callback null, null, allErrors
				else
					callback results.join("\n\n")
		
		if inputs.length > 0 then recursiveRender 0 else callback ""
	
	renderIndexContent: (input, options, callback) ->
		# By default, index content will be treated just like normal content.
		@renderContent input, options, callback
	
	renderAppTreeContent: (input, options, callback) ->
		# By default, the raw input of each file goes into the app tree.
		callback input
	
	postProcessContent: (input, options, callback) ->
		# By default, post processing does nothing.
		callback input


# A class that represents a directory. The app tree is comprised of these and SquireFiles.
class exports.SquireDirectory extends exports.Squire
	constructor: (options = {}) ->
		super
		@path          = options.path
		@publicPath    = options.publicPath
		pathComponents = @path.split "/"
		@name          = pathComponents[pathComponents.length - 1]
		@directories   = {}
		@files         = {}
	
	getPath: (path) ->
		path = path[1..] while path[0] is "/"
		
		if path.length is 0
			this
		else
			node           = this
			pathComponents = path.split "/"
			
			for component, index in pathComponents
				nextNode = node.directories[component]
				nextNode = node.files[component] if not nextNode? and index is pathComponents.length - 1
				node     = nextNode
				break unless node?
			
			node
	
	walk: (callback) ->
		callback this
		directory.walk callback for name, directory of @directories


# A class that represents a file. The app tree is comprised of these and SquireDirectories.
class exports.SquireFile extends exports.Squire
	constructor: (options = {}) ->
		super
		@path       = options.path
		@publicPath = options.publicPath
		urlInfo     = @getUrlInfo @path
		@name       = urlInfo.fileName
		@plugin     = options.plugin
		@content    = options.content
