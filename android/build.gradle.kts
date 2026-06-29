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
subprojects {
    project.evaluationDependsOn(":app")
}

// Force every Android plugin/module to compile against SDK 36.
// Some transitive plugins (e.g. flutter_plugin_android_lifecycle) now require
// compileSdk >= 36, while others (e.g. file_picker) still ship compiled against
// 34. Overriding here keeps all subprojects aligned without editing each plugin.
subprojects {
    val applyCompileSdk = {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            try {
                androidExt.javaClass
                    .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    .invoke(androidExt, 36)
            } catch (_: Exception) {
                // Not all "android" extensions expose compileSdkVersion(int); ignore.
            }
        }
    }
    // `:app` is evaluated early via evaluationDependsOn above, so we can't always
    // register an afterEvaluate hook — configure directly when already evaluated.
    if (project.state.executed) {
        applyCompileSdk()
    } else {
        afterEvaluate { applyCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
