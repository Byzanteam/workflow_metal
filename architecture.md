# Supervisor tree

## Hierarch
- WorkflowApplicationSupervisor(Supervisor)
  - Registry(Registry)
  - Config(Agent)
  - WorkflowsSupervisor(DynamicSupervisor)
    - Storage(GenServer)
    - WorkflowSupervisor(Supervisor)
      - Workflow(GenServer)
      - WorkflowVersionManager(DynamicSupervisor)
        - VersionedWorkflow(GenServer)
      - CaseSupervisor(DynamicSupervisor)
        - Case(GenServer)
      - VertexSupervisor(DynamicSupervisor)
        - Vertex(GenServer)
          - Vertex.Arc
          - Vertex.Transition
          - Vertex.Task

## functions
create_workflow(application, workflow_id)

create_workflow_version(application, workflow_id, version)
deploy_workflow_version(application, workflow_id, version)

create_workflow_case(application, workflow_id, version \\ :current)


## Lagecy
- WorkflowApplicationSupervisor(Supervisor)
  - Registry(Registry)
  - WorkflowSupervisor(DynamicSupervisor)
    - Workflow(GenServer)
      - WorkflowVersionManager(DynamicSupervisor)
        - VersionedWorkflow(GenServer)
          - CaseSupervisor(DynamicSupervisor)
            - Case(GenServer)
              - VertexSupervisor(DynamicSupervisor)
                - Vertex(GenServer)
                  - Vertex.Arc
                  - Vertex.Transition
