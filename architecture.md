# Supervisor tree

## Hierarch
- WorkflowApplicationSupervisor(Supervisor)
  - Registry(Registry)
  - Config(Agent)
  - Storage
  - WorkflowsSupervisor(DynamicSupervisor)
    - WorkflowSupervisor(Supervisor)
      - Workflow(GenServer)
      - TaskSupervisor(DynamicSupervisor)
        - Task(GenServer)
      - CaseSupervisor(DynamicSupervisor)
        - Case(GenServer)
      - VertexSupervisor(DynamicSupervisor)
        - Vertex(GenServer)
          - Vertex.Arc
          - Vertex.Transition
          - Vertex.Task

## functions
create_workflow(application, workflow_schema)

create_workflow_case(application, workflow_id)


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
