##
## plugins/coffeescript.coffee
## 
## A plugin to handle CoffeeScript files.
##

lib =
	fs:     require "fs"
	squire: require "../squire"
	coffee: require "coffee-script"
	merge:  require "deepmerge"
	uglify: require "uglify-js"
	_:      require "underscore"

class exports.Plugin extends lib.squire.SquirePlugin
	inputExtensions: ["coffee"]
	outputExtension: "js"
	
	configDefaults:
		global:
			templatePlugin: "jade"
			localsProperty: "locals"
	
	renderContent: (input, options, callback) ->
		js     = null
		errors = null
		
		try
			js = lib.coffee.compile input, options.compilerOptions or {}
		catch compileError
			errors = [@createCoffeeScriptError compileError, options.url]
		
		if @config.minify and js?
			try
				syntaxTree = lib.uglify.parser.parse js
				syntaxTree = lib.uglify.uglify.ast_mangle syntaxTree
				syntaxTree = lib.uglify.uglify.ast_squeeze syntaxTree
				js         = lib.uglify.uglify.gen_code syntaxTree
			catch parseError
				# This should hopefully never happen -- if we get here it means that the JavaScript
				# generated by CoffeeScript couldn't be parsed by uglify-js.
				errors = [@createCoffeeScriptError parseError, options.url, "minifying"] unless errors?
		
		callback js, null, errors
	
	renderContentList: (inputs, options, callback) ->
		# We first need to check for syntax errors. We have to do this as a separate step because
		# when we actually compile our source, we are compiling a combined file, which causes us to
		# lose filename and line number information when we have syntax errors.
		allErrors      = []
		builtFileCount = 0
		
		for input, index in inputs
			url = options.urls?[index]
			
			@renderContent input, (if url? then { url: url } else {}), (output, data, errors = []) =>
				allErrors = allErrors.concat errors
				
				if ++builtFileCount is inputs.length
					if allErrors.length > 0
						callback null, null, allErrors
					else
						@renderContent inputs.join("\n\n"), options, callback
	
	renderIndexContent: (input, options, callback) ->
		templatePlugin = @loadPlugin @config.templatePlugin
		
		if templatePlugin?
			try
				input = lib.coffee.eval input
			catch error
				callback null, null, [@createCoffeeScriptError error, options.url]
				return
			
			dataFunction = input.pageData or input.pageDataAsync
			
			if typeof(dataFunction) is "function"
				functionType = if input.pageData? then "sync" else "async"
				
				done = (data) =>
					if data?.template?
						localsProperty = @config.localsProperty
						templateUrl    = "#{@appPath}/#{data.template}"
						template       = @loadTextFile data.template
						
						if template?
							templateOptions                 = { url: templateUrl }
							templateOptions[localsProperty] = { data: data }
							templatePlugin.renderIndexContent template, templateOptions, callback
						else
							callback null, null, [@createError "Template file does not exist at #{templateUrl}."]
					else
						super
				
				if functionType is "sync"
					done dataFunction(@app, lib._)
				else
					dataFunction @app, lib._, (data) => done data
			else
				super
		else
			super
	
	createCoffeeScriptError: (error, url, verb = "compiling") ->
		message = error.toString().split("\n")[0]
		@createError "There was an error while #{verb} your CoffeeScript:", message, url
