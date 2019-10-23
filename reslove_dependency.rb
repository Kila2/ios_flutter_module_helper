#!/usr/bin/ruby
require 'yaml'
require 'fileutils'
require 'json'
require 'set'

class BaseBuilder
    def shcmd(cmd)
        puts "🍎🍎cmd #{cmd}"
        system(cmd)
        if($?.exitstatus != 0)
            raise $?
        end
    end
    #压缩Zip
    def zip(workdir,src,dest,backdir)
        Dir::chdir(workdir)
        puts workdir
        shcmd("zip -r #{dest} ./#{src}")
        Dir::chdir(backdir)
    end
    #合并架构
    def lipo(source1 ,source2 ,dest)
        cmd = "lipo -create #{source1} #{source2} -output #{dest}"
        shcmd(cmd)
    end
end

class FlutterBuilder < BaseBuilder
    def initialize(srcroot,podname,pubspec_path = nil,flutter_framework_path = nil,custom_lib_paths = [])
        @srcroot,@podname,@pubspec_path,@flutter_framework_path,@custom_lib_paths = srcroot,podname,pubspec_path,flutter_framework_path,custom_lib_paths
        if @custom_lib_paths == nil 
            @custom_lib_paths = []
        end
        if pubspec_path == nil
            pubspec_path = "#{srcroot}/pubspec.yaml"
        end
        @pubspec = YAML.load(File.open(pubspec_path))
        @podTemplatePath = "#{srcroot}/Template.podspec"
        @podSpecPath = "#{srcroot}/ios_deploy/#{PODNAME}.podspec"
        @userName = `git config user.name`.strip!
        @userEmail = `git config user.email`.strip!
        debugBuiltProductsDir = `xcodebuild -showBuildSettings -workspace #{srcroot}/ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -arch x86_64 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO EXPANDED_CODE_SIGN_IDENTITY=- EXPANDED_CODE_SIGN_IDENTITY_NAME=- | grep "BUILT_PRODUCTS_DIR = /" | sed 's/[ ]*BUILT_PRODUCTS_DIR = //'`
        @debugBuiltProductsDir = debugBuiltProductsDir[0,debugBuiltProductsDir.length-1]
        releaseBuiltProductsDir = `xcodebuild -showBuildSettings -workspace #{srcroot}/ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos -arch arm64 -arch armv7 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO EXPANDED_CODE_SIGN_IDENTITY=- EXPANDED_CODE_SIGN_IDENTITY_NAME=- FLUTTER_BUILD_MODE=release | grep "BUILT_PRODUCTS_DIR = /" | sed 's/[ ]*BUILT_PRODUCTS_DIR = //'`
        @releaseBuiltProductsDir = releaseBuiltProductsDir[0,releaseBuiltProductsDir.length-1]
        if @flutter_framework_path == nil 
            @flutter_framework_path = "#{@srcroot}/.ios/Flutter/engine"
            if isModule() == false
                @flutter_framework_path = "#{@srcroot}/ios/Flutter"
            end
        end
    end

    def isModule 
        return @pubspec['flutter']['module'] != nil
    end

    def build
        prepareFlutterBridge()
        podinstall()
        xcodebuild()
        findFlutterPlugin()
        prepareNoVersionPODS()
        findPluginDependency()
    end

    def cleanCache
        puts "🍎cleanCache"
        puts `rm -rf #{@srcroot}/build`
        puts `mkdir #{@srcroot}/build`
    end

    def prepareFlutterBridge
        puts "🍎prepareFlutterBridge"
        if File.directory?("#{@srcroot}/ios/FlutterBridge")
            puts `rm -rf #{@srcroot}/ios/#{@podname}Bridge`
            podfilePath = "#{@srcroot}/ios/Podfile"
            system("sed -i .bak 's/FlutterBridge/#{@podname}Bridge/' #{podfilePath}")
            system("sed -i .bak 's/.\\\/FlutterBridge/#{@podname}Bridge/' #{podfilePath}")
            flutter_bridge_podspec = "#{@srcroot}/ios/FlutterBridge/FlutterBridge.podspec"
            system("sed -i .bak 's/FlutterBridge/#{@podname}Bridge/' #{flutter_bridge_podspec}")
            system("sed -i .bak 's/FlutterBridge\\\//#{@podname}Bridge\\\//' #{flutter_bridge_podspec}")
            system("sed -i .bak 's/\${USER_NAME}/#{@userName}/' #{flutter_bridge_podspec}")
            system("sed -i .bak 's/\${USER_EMAIL}/#{@userEmail}/' #{flutter_bridge_podspec}")
            FileUtils.mv("#{@srcroot}/ios/FlutterBridge/FlutterBridge","#{@srcroot}/ios/FlutterBridge/#{@podname}Bridge")
            FileUtils.mv("#{@srcroot}/ios/FlutterBridge/FlutterBridge.podspec","#{@srcroot}/ios/FlutterBridge/#{@podname}Bridge.podspec")
            FileUtils.mv("#{@srcroot}/ios/FlutterBridge","#{@srcroot}/ios/#{@podname}Bridge")
        end
    end

    def podinstall
        puts "🍎podinstall"
        Dir::chdir("#{@srcroot}/ios")
        if File.exist?("TaobaoEnv")
            shcmd("source ~/.tbenv/bundler-exec.sh && pod install --no-repo-update")
        else
            shcmd("pod install")    
        end
        Dir::chdir("#{@srcroot}")
    end

    def xcodebuild
        puts "🍎xcodebuild"
        #BUG XCode11无法打armv7
        shcmd("xcodebuild clean build -workspace #{@srcroot}/ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -arch x86_64 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO EXPANDED_CODE_SIGN_IDENTITY=- EXPANDED_CODE_SIGN_IDENTITY_NAME=-")
        raise "文件不存在 #{@debugBuiltProductsDir}" unless File.directory?(@debugBuiltProductsDir)
        shcmd("xcodebuild build -workspace #{@srcroot}/ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos -arch arm64 -arch armv7 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO EXPANDED_CODE_SIGN_IDENTITY=- EXPANDED_CODE_SIGN_IDENTITY_NAME=- FLUTTER_BUILD_MODE=release")
        raise "文件不存在 #{@releaseBuiltProductsDir}" unless File.directory?(@releaseBuiltProductsDir)
    end
    
    def findFlutterPlugin
        puts "🍎findFlutterPlugin"
        plugin_podspec_names = []
        pluginDir = getPluginDir()
        pluginDir&.each do |filename|
            plugin_podspec_names.push(File.basename(filename))
        end 
        puts plugin_podspec_names
        @plugin_podspec_names = plugin_podspec_names
    end

    def prepareNoVersionPODS
        puts "🍎prepareNoVersionPODS"
        podlock = YAML.load(File.open("#{@srcroot}/ios/Podfile.lock"))
        pods = podlock["PODS"]
        no_version_pods = []
        pods&.each do |element|
            if element.class == Hash
                new_key = element.keys[0].to_s.gsub(/ \(.+\)/, '')
                new_value = []
                element.values[0]&.each do |v|
                    new_value.push(v.gsub(/ \(.+\)/, ''))
                end
                no_version_pods.push(Hash[new_key => new_value])
            else
                new_key = element.to_s.gsub(/ \(.+\)/, '')
                no_version_pods.push(new_key)
            end
        end
        @pods = no_version_pods
        puts @pods
    end
    
    def findPluginDependency
        puts "🍎findPluginDependency"
        def reslove_podfile(parent_pod_names,no_version_pods)
            children = []
            if parent_pod_names.length == 0
                return children
            end
            parent_pod_names&.each do |name|
                e = nil
                @pods&.each do |k|
                    if k.class == Hash && k.keys[0] == name
                        e = k
                    end
                end
                if e.class == Hash
                e.values[0]&.each do |v|
                    if !parent_pod_names.include?(v) && v != "Flutter"
                        children.push(v)
                    end
                end
                end
            end
            return children + reslove_podfile(children,@pods)
        end
        @dependencys = reslove_podfile(@plugin_podspec_names,@pods)
        puts @dependencys
    end

    def modifyPodspec
        puts "🍎modifyPodspec"
        #step.3修改podspec
        FileUtils.cp("#{@podTemplatePath}", "#{@podSpecPath}")
        system("sed -i .bak 's/\${POD_NAME}/#{@podname}/' #{@podSpecPath}")
        system("sed -i .bak 's/spec_path:.*/spec_path: .\\\/ios_deploy\\\/#{@podname}.podspec.json/' #{@srcroot}/module_ci.ios.yml")
        system("sed -i .bak 's/\${USER_NAME}/#{@userName}/' #{@podSpecPath}")
        system("sed -i .bak 's/\${USER_EMAIL}/#{@userEmail}/' #{@podSpecPath}")
        #把podsepc转换成json格式
        system("pod ipc spec #{@podSpecPath} > #{@podSpecPath}.json")
        #读取json文件
        json = File.read("#{@podSpecPath}.json")
        obj = JSON.parse(json)
        #添加dependencies
        obj["dependencies"] = {}
        @dependencys.each do |dependency| 
            obj["dependencies"][dependency] = []
        end
        #添加vendored_frameworks
        obj["vendored_frameworks"] = []
        @vendored_frameworks&.each do |vendor|
            obj["vendored_frameworks"].push(vendor)
        end
        #保存json文件
        File.open("#{@podSpecPath}.json", 'w') do |f|
            f.puts JSON.pretty_generate(obj)
            puts obj
        end
    end

    def getPluginDir 
        if isModule()
            symlinks = "#{@srcroot}/.ios/Flutter/.symlinks"
            return Dir["#{symlinks}/**"]
        else
            symlinks = "#{@srcroot}/ios/.symlinks"
            return Dir["#{symlinks}/plugins/**"]
        end
    end

    def prepareAppFramework(copyList,lipoList,zipList,vendored_frameworks)
        puts "🍎prepareAppFramework"
        fn = "App"
        copyList.push({"src"=>"#{@debugBuiltProductsDir}/Runner.app/Frameworks/#{fn}.framework","dest"=>"#{@srcroot}/build/#{fn}.framework"})
        copyList.push({"src"=>"#{@releaseBuiltProductsDir}/Runner.app/Frameworks/#{fn}.framework","dest"=>"#{@srcroot}/build/#{fn}-iphoneos.framework"})
        lipoList.push({"src1"=>"#{@srcroot}/build/#{fn}.framework/#{fn}","src2"=>"#{@srcroot}/build/#{fn}-iphoneos.framework/#{fn}","dest"=>"#{@srcroot}/build/#{fn}.framework/#{fn}"})    
        zipList["#{fn}.framework"] = "#{@srcroot}/build"
        vendored_frameworks.add("#{fn}.framework")
    end

    def prepareFlutterFramework(zipList,vendored_frameworks)
        puts "🍎prepareFlutterFramework"
        zipList["Flutter.framework"] = @flutter_framework_path
        vendored_frameworks.add("Flutter.framework")
    end

    def copylib(copyList)
        puts "🍎copylib"
        copyList&.each do |e|
            FileUtils.copy_entry(e["src"], e["dest"])
        end
    end

    def lipolib(lipoList)
        puts "🍎lipolib"
        lipoList&.each do |e|
            lipo(e["src1"],e["src2"],e["dest"])
            x86 = `file #{e["src1"]} |grep "for architecture x86_64"`
            armv7 = `file #{e["src1"]} |grep "for architecture armv7"`
            arm64 = `file #{e["src1"]} |grep "for architecture arm64"`
            raise "x86不存在 #{e['src1']}" unless x86 != ""
            if !e["src1"].include?("App.framework") 
                raise "armv7不存在 #{e['src1']}" unless armv7 != ""
            end
            raise "arm64不存在 #{e['src1']}" unless arm64 != ""
        end
    end

    def zipFiles(zipList)
        puts "🍎zipFiles"
        zipList&.each do |key,value|
            zip(value,key,"#{@srcroot}/ios_deploy/Flutter.zip",@srcroot)
        end
    end
    
end

class DynamicFrameworkBuilder < FlutterBuilder
    def build
        super
        buildDynamicFramework()
        modifyPodspec()
    end

    def buildDynamicFramework
        puts "🍎buildDynamicFramework"
        copyList = []
        lipoList = []
        zipList = Hash[]
        vendored_frameworks = Set[]
        perpareCustomLib(copyList,lipoList,zipList,vendored_frameworks)
        prepareAppFramework(copyList,lipoList,zipList,vendored_frameworks)
        prepareFlutterFramework(zipList,vendored_frameworks)
        prepareFlutterPluginRegistrant(copyList,lipoList,zipList,vendored_frameworks)
        preparePlugin(copyList,lipoList,zipList,vendored_frameworks)
        copylib(copyList)
        lipolib(lipoList)
        zipFiles(zipList)
        @vendored_frameworks = vendored_frameworks
    end

    def perpareCustomLib(copyList,lipoList,zipList,vendored_frameworks)
        puts "🍎perpareCustomLib"
        @custom_lib_paths.push("#{@srcroot}/ios/#{@podname}Bridge")
        @custom_lib_paths&.each do | dir |
            fn = File.basename(dir)
            if File.directory?(dir)
                copyList.push({"src"=>"#{@debugBuiltProductsDir}/#{fn}/#{fn}.framework","dest"=>"#{@srcroot}/build/#{fn}.framework"})
                copyList.push({"src"=>"#{@releaseBuiltProductsDir}/#{fn}/#{fn}.framework","dest"=>"#{@srcroot}/build/#{fn}-iphoneos.framework"})
                lipoList.push({"src1"=>"#{@srcroot}/build/#{fn}.framework/#{fn}","src2"=>"#{@srcroot}/build/#{fn}-iphoneos.framework/#{fn}","dest"=>"#{@srcroot}/build/#{fn}.framework/#{fn}"})
                vendored_frameworks.add("#{fn}.framework")
                zipList["#{fn}.framework"] = "#{@srcroot}/build"
            end
        end
    end

    def prepareFlutterPluginRegistrant(copyList,lipoList,zipList,vendored_frameworks)
        puts "🍎prepareFlutterPluginRegistrant"
        fn = "FlutterPluginRegistrant"
        if File.directory?("#{@releaseBuiltProductsDir}/#{fn}")
            copyList.push({"src"=>"#{@debugBuiltProductsDir}/#{fn}/#{fn}.framework","dest"=>"#{@srcroot}/build/#{fn}.framework"})
            copyList.push({"src"=>"#{@releaseBuiltProductsDir}/#{fn}/#{fn}.framework","dest"=>"#{@srcroot}/build/#{fn}-iphoneos.framework"})
            lipoList.push({"src1"=>"#{@srcroot}/build/#{fn}.framework/#{fn}","src2"=>"#{@srcroot}/build/#{fn}-iphoneos.framework/#{fn}","dest"=>"#{@srcroot}/build/#{fn}.framework/#{fn}"})
            vendored_frameworks.add("#{fn}.framework")
            zipList["#{fn}.framework"] = "#{@srcroot}/build"
        end
    end

    def preparePlugin(copyList,lipoList,zipList,vendored_frameworks)
        puts "🍎preparePlugin"
        @plugin_podspec_names&.each do |plugin|
            fn = plugin
            if File.directory?("#{@releaseBuiltProductsDir}/#{fn}")
                copyList.push({"src"=>"#{@debugBuiltProductsDir}/#{fn}/#{fn}.framework","dest"=>"#{@srcroot}/build/#{fn}.framework"})
                copyList.push({"src"=>"#{@releaseBuiltProductsDir}/#{fn}/#{fn}.framework","dest"=>"#{@srcroot}/build/#{fn}-iphoneos.framework"})
                lipoList.push({"src1"=>"#{@srcroot}/build/#{fn}.framework/#{fn}","src2"=>"#{@srcroot}/build/#{fn}-iphoneos.framework/#{fn}","dest"=>"#{@srcroot}/build/#{fn}.framework/#{fn}"})
                vendored_frameworks.add("#{fn}.framework")
                zipList["#{fn}.framework"] = "#{@srcroot}/build"
            end
        end
    end
end

class StaticFrameworkBuilder < FlutterBuilder
    def build
        super
        buildStaticFramework()
        modifyPodspec()
    end

    def prepareFlutterPluginRegistrant(copyList,lipoList,vendored_frameworks)
        puts "🍎prepareFlutterPluginRegistrant"
        fn = "FlutterPluginRegistrant"
        if File.directory?("#{@releaseBuiltProductsDir}/#{fn}")
            copyList.push({"src"=>"#{@debugBuiltProductsDir}/#{fn}/lib#{fn}.a","dest"=>"#{@srcroot}/build/lib#{fn}.a"})
            copyList.push({"src"=>"#{@releaseBuiltProductsDir}/#{fn}/lib#{fn}.a","dest"=>"#{@srcroot}/build/lib#{fn}-iphoneos.a"})
            lipoList.push({"src1"=>"#{@srcroot}/build/lib#{fn}.a","src2"=>"#{@srcroot}/build/lib#{fn}-iphoneos.a","dest"=>"#{@srcroot}/build/lib#{fn}.a"})
            vendored_frameworks.add("#{fn}.framework")
        end
    end

    def preparePlugin(copyList,lipoList)
        puts "🍎preparePlugin"
        @plugin_podspec_names&.each do |plugin|
            fn = plugin
            if File.directory?("#{@releaseBuiltProductsDir}/#{fn}")
                copyList.push({"src"=>"#{@debugBuiltProductsDir}/#{fn}/lib#{fn}.a","dest"=>"#{@srcroot}/build/lib#{fn}.a"})
                copyList.push({"src"=>"#{@releaseBuiltProductsDir}/#{fn}/lib#{fn}.a","dest"=>"#{@srcroot}/build/lib#{fn}-iphoneos.a"})
                lipoList.push({"src1"=>"#{@srcroot}/build/lib#{fn}.a","src2"=>"#{@srcroot}/build/lib#{fn}-iphoneos.a","dest"=>"#{@srcroot}/build/lib#{fn}.a"})
            end
        end
    end

    def makeFrameworkAndCopyHeader(lipoList,zipList,vendored_frameworks)
        puts "🍎makeFrameworkAndCopyHeader"
        lipoList&.each do |e|
            if e["dest"].include?("App.framework")
                puts "🍎 ignore #{e['dest']}"
            else
                filename = File.basename(e["dest"])
                name = filename[3,filename.length-5]
                #重命名libXXX.a成XXX
                FileUtils.mv(e["dest"],"#{@srcroot}/build/#{name}")
                framework = mkFramework("#{@srcroot}/build",name)
                zipList["#{framework}"] = "#{@srcroot}/build"
                vendored_frameworks.add(framework)
            end
        end
    end
    
    #制作Framework
    def mkFramework(dir,liba)
        Dir::chdir(dir)
        FileUtils.rm_rf("#{liba}.framework")
        FileUtils.mkdir("#{liba}.framework")
        FileUtils.mv("./#{liba}","./#{liba}.framework")
        #FileUtils.copy_entry("#{srcroot}/ios/Pods/Headers/Public/#{liba}","./#{liba}.framework/Headers")
        headers = "#{@srcroot}/ios/Pods/Headers/Public/#{liba}"
        if File.directory?(headers)
            shcmd("cp -r #{headers} ./#{liba}.framework/Headers")
        end
        #copyBundle
        bundles = Dir["#{@releaseBuiltProductsDir}/#{liba}/*.bundle"]
        bundles.each do |bundle|
            nameext = File.basename(bundle)
            #copy bundle到framework
            FileUtils.copy_entry(bundle,"#{@srcroot}/build/#{liba}.framework/#{nameext}")
            puts "🚽#{bundle} ,#{@srcroot}/build/#{nameext}"
        end
        Dir::chdir(@srcroot)
        return "#{liba}.framework"
    end

    def perpareCustomLib(copyList,lipoList,vendored_frameworks)
        puts "🍎perpareCustomLib"
        @custom_lib_paths.push("#{@srcroot}/ios/#{@podname}Bridge")
        @custom_lib_paths&.each do | dir |
            fn = File.basename(dir)
            if File.directory?(dir)
                copyList.push({"src"=>"#{@debugBuiltProductsDir}/#{fn}/lib#{fn}.a","dest"=>"#{@srcroot}/build/lib#{fn}.a"})
                copyList.push({"src"=>"#{@releaseBuiltProductsDir}/#{fn}/lib#{fn}.a","dest"=>"#{@srcroot}/build/lib#{fn}-iphoneos.a"})
                lipoList.push({"src1"=>"#{@srcroot}/build/lib#{fn}.a","src2"=>"#{@srcroot}/build/lib#{fn}-iphoneos.a","dest"=>"#{@srcroot}/build/lib#{fn}.a"})
                vendored_frameworks.add("#{fn}.framework")
            end
        end
    end

    def buildStaticFramework
        puts "🍎buildStaticFramework"
        copyList = []
        lipoList = []
        zipList = Hash[]
        vendored_frameworks = Set[]
        perpareCustomLib(copyList,lipoList,vendored_frameworks)
        prepareAppFramework(copyList,lipoList,zipList,vendored_frameworks)
        prepareFlutterFramework(zipList,vendored_frameworks)
        prepareFlutterPluginRegistrant(copyList,lipoList,vendored_frameworks)
        preparePlugin(copyList,lipoList)
        puts "🍎zipList"
        puts zipList
        puts "🍎copyList"
        puts copyList
        puts "🍎lipoList"
        puts lipoList
        copylib(copyList)
        lipolib(lipoList)
        makeFrameworkAndCopyHeader(lipoList,zipList,vendored_frameworks)
        #TODO:支持swift
        #buildMoudleHelper()
        zipFiles(zipList)
        @vendored_frameworks = vendored_frameworks
    end
end

puts "running reslove_dependency.rb"
srcroot = ARGV.first
PODNAME = "TestPodName"
LIBS = nil
PUBSPEC_PATH = nil
FLUTTER_FRAMEWORK_PATH = nil

begin 
    StaticFrameworkBuilder.new(srcroot,PODNAME,PUBSPEC_PATH,FLUTTER_FRAMEWORK_PATH,LIBS).build()
rescue Exception => e
    puts e.message
    puts e.backtrace.inspect
ensure 
    #.. 最后确保执行
    #.. 这总是会执行
end
