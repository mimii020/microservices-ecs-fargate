resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "${var.project}-pipeline-artifacts-${random_id.log_suffix.hex}"
  force_destroy = true

  tags = {
    Name = "${var.project}-pipeline-artifacts"
  }
}


resource "aws_codebuild_project" "app_build" {
  name          = "${var.project}-build"
  description   = "Build Docker image and push to ECR"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 20

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  tags = {
    Name = "${var.project}-build"
  }
}



resource "aws_codepipeline" "app_pipeline" {
  name     = "${var.project}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = "mimii020/microservices-ecs-fargate"
        BranchName       = "sandbox-deployment"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildAction"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.app_build.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployAction"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["BuildOutput"]

      configuration = {
        ApplicationName                = aws_codedeploy_app.ecs_app.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.ecs_dg.deployment_group_name
        TaskDefinitionTemplateArtifact = "BuildOutput"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "BuildOutput"
        AppSpecTemplatePath            = "appspec.yml"
        Image1ArtifactName             = "BuildOutput"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }

  tags = {
    Name = "${var.project}-pipeline"
  }
}