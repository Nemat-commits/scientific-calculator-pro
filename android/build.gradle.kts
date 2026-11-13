allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Plugins that still pin an old compile SDK (flutter_displaymode 0.6.0 uses
// API 33) fail AGP's AAR-metadata check, because current AndroidX artifacts
// need API 34+ at compile time. Lift such plugin modules to the SDK level the
// app itself is compiled against. This has to be registered before the
// `evaluationDependsOn` block below, so it runs ahead of AGP's own
// after-evaluate hook.
val pluginCompileSdkFloor = 36
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.findByName("android")?.withGroovyBuilder {
                val declared = getProperty("compileSdk") as? Int
                if (declared != null && declared < pluginCompileSdkFloor) {
                    logger.lifecycle("${project.name}: compileSdk $declared -> $pluginCompileSdkFloor")
                    setProperty("compileSdk", pluginCompileSdkFloor)
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
