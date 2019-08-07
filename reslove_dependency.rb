#!/usr/bin/ruby
require 'yaml'
require 'fileutils'
require 'json'

srcroot = ARGV.first
PODNAME = "TestPodName"
PodTemplate = "#{srcroot}/Template.podspec"
PodSpec = "#{srcroot}/ios_deploy/#{PODNAME}.podspec"
USER_NAME = `git config user.name`.strip!
USER_EMAIL = `git config user.email`.strip!

def main
    puts "running reslove_dependency.rb"
    srcroot = ARGV.first
    #BUG HardCode
    isFramework = 0
    #压缩Zip
    def zip(dir,filename)
        srcroot = ARGV.first
        Dir::chdir(dir)
        cmd = "zip -rm #{srcroot}/Flutter.zip ./#{filename}"
        puts cmd
        system(cmd)
        Dir::chdir(srcroot)
    end
    #合并架构
    def lipo(source1 ,source2 ,dest)
        cmd = "lipo -create #{source1} #{source2} -output #{dest}"
        puts cmd
        system(cmd)
    end

    #制作Framework #BUG没有考虑Bundle
    def mkFramework(dir,liba)
        srcroot = ARGV.first
        Dir::chdir(dir)
        FileUtils.rm_rf("#{liba}.framework")
        FileUtils.mkdir("#{liba}.framework")
        FileUtils.mv("./#{liba}","./#{liba}.framework")
        #FileUtils.copy_entry("#{srcroot}/ios/Pods/Headers/Public/#{liba}","./#{liba}.framework/Headers")
        cmd = "cp -r #{srcroot}/ios/Pods/Headers/Public/#{liba} ./#{liba}.framework/Headers"
        puts cmd
        system(cmd)
        Dir::chdir(srcroot)
        return "#{liba}.framework"
    end
    puts "step.0"
    #step.0获取需要忽略的framework
    podlock = YAML.load(File.open("#{srcroot}/ios/Podfile.lock"))
    dependencys = []
    repos = podlock["SPEC REPOS"]
    repos.each do |key,value|
        repos[key].each do |dependency|
            dependencys.push(dependency) 
        end
    end
    puts "step.1"
    #step.1 处理需要压缩的Zip
    FileUtils.copy_entry("#{srcroot}/build/miniapp/iphonesimulator/Runner.app/Frameworks/App.framework", "#{srcroot}/build/App.framework")
    FileUtils.copy_entry("#{srcroot}/build/miniapp/iphoneos/Runner.app/Frameworks/App.framework", "#{srcroot}/build/App-device.framework")
    lipo("#{srcroot}/build/App.framework/App","#{srcroot}/build/App-device.framework/App","#{srcroot}/build/App.framework/App")
    FileUtils.rm_rf("#{srcroot}/build/App-device.framework")

    all_vendors=['App.framework','Flutter.framework']
    zipFrameworks = Hash[
        "Flutter.framework" => "#{srcroot}/.ios/Flutter/engine",
        "App.framework" => "#{srcroot}/build",
    ]
    if isFramework == 1
        #打包成framework
        vendor_dir = Dir["#{srcroot}/build/miniapp/iphoneos/*.framework"]
        vendor_dir.each do |filename|
            name = File.basename(filename, '.framework')
            nameext = File.basename(filename)
            if (nameext.include? "Pods_Runner.framework") || (dependencys.include? name)
                puts "🍎 ignore #{nameext}"
            else
                FileUtils.copy_entry("#{srcroot}/build/miniapp/iphonesimulator/#{nameext}", "#{srcroot}/build/#{name}-sim.framework")
                FileUtils.copy_entry("#{srcroot}/build/miniapp/iphoneos/#{nameext}", "#{srcroot}/build/#{nameext}")
                lipo("#{srcroot}/build/#{name}.framework/#{name}","#{srcroot}/build/#{name}-sim.framework/#{name}","#{srcroot}/build/#{name}.framework/#{name}")
                zipFrameworks["#{nameext}"] = "#{srcroot}/build"
                all_vendors.push(nameext)
                FileUtils.rm_rf("#{srcroot}/build/#{name}-sim.framework")
            end
        end
        #step.2压缩Zip
        zipFrameworks.each do |nameext,dir|
            zip(dir,nameext);
            if nameext.include? "Flutter.framework"
                puts "🍎 ignore #{nameext}"
            elsif nameext.include? "App.framework"
                puts "🍎 ignore #{nameext}"
            else
                FileUtils.rm_rf("#{srcroot}/build/#{nameext}")
            end
        end
    else
        #打包成lib.a
        lib_dir = Dir["#{srcroot}/build/miniapp/iphoneos/*.a"]
        lib_dir.each do |filename|
            name = File.basename(filename, '.a')
            nameext = File.basename(filename)
            puts "🌰#{dependencys}"
            puts "🌰#{name}"
            if (nameext.include? "libPods-Runner.a") || (dependencys.include? name[3,name.length])
                puts "🍎 ignore #{nameext}"
            else
                FileUtils.copy_entry("#{srcroot}/build/miniapp/iphonesimulator/#{nameext}", "#{srcroot}/build/#{name}-sim.a")
                FileUtils.copy_entry("#{srcroot}/build/miniapp/iphoneos/#{nameext}", "#{srcroot}/build/#{nameext}")
                lipo("#{srcroot}/build/#{name}.a","#{srcroot}/build/#{name}-sim.a","#{srcroot}/build/#{name}.a")
                FileUtils.rm_rf("#{srcroot}/build/#{name}-sim.a")
                #liba包装成framework
                if nameext.include? "Flutter.framework"
                    puts "🍎 ignore #{nameext}"
                elsif nameext.include? "App.framework"
                    puts "🍎 ignore #{nameext}"
                else
                    opath = "#{srcroot}/build/#{nameext}"
                    name = nameext[3,nameext.length-5]
                    dpath = "#{srcroot}/build/#{name}"
                    #重命名libXXX.a成XXX
                    FileUtils.mv(opath,dpath);
                    #制作Framework
                    framework = mkFramework("#{srcroot}/build",name);
                    zipFrameworks["#{framework}"] = "#{srcroot}/build"
                    all_vendors.push(framework)
                end
            end
        end
        #step.2压缩Zip
        zipFrameworks.each do |nameext,dir|
            zip(dir,nameext);
            if nameext.include? "Flutter.framework"
                puts "🍎 ignore #{nameext}"
            elsif nameext.include? "App.framework"
                puts "🍎 ignore #{nameext}"
            else
                FileUtils.rm_rf("#{srcroot}/build/#{nameext}")
            end
        end
    end

    puts "step.3"
    #step.3修改podspec
    FileUtils.cp("#{PodTemplate}", "#{PodSpec}")
    cmd = "sed -i .bak 's/\${POD_NAME}/#{PODNAME}/' #{PodSpec}"
    system(cmd)
    cmd = "sed -i .bak 's/\${USER_NAME}/#{USER_NAME}/' #{PodSpec}"
    system(cmd)
    cmd = "sed -i .bak 's/\${USER_EMAIL}/#{USER_EMAIL}/' #{PodSpec}"
    system(cmd)
    #把podsepc转换成json格式
    cmd = "pod ipc spec #{PodSpec} > #{PodSpec}.json"
    puts cmd
    system(cmd)
    #读取json文件
    json = File.read("#{PodSpec}.json")
    obj = JSON.parse(json)
    #添加dependencies
    obj["dependencies"] = {}
    dependencys.each do |dependency| 
        obj["dependencies"][dependency] = []
    end
    
    #添加vendored_frameworks
    obj["vendored_frameworks"] = []
    all_vendors.each do |vendor|
        obj["vendored_frameworks"].push(vendor)
    end
    puts all_vendors
    #保存json文件
    File.open("#{PodSpec}.json", 'w') do |f|
        f.puts JSON.pretty_generate(obj)
        puts obj
    end
    FileUtils.mv("#{srcroot}/Flutter.zip","#{srcroot}/ios_deploy/Flutter.zip")

    
end

begin 
    main()
rescue Exception => e
    puts e.message
    puts e.backtrace.inspect
ensure 
    #.. 最后确保执行
    #.. 这总是会执行
end
