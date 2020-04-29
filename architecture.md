# Supervisor tree

## Hierarch
- WorkflowApplicationSupervisor(Supervisor)
  - Registry(Registry)
  - Config(Agent)
  - Storage
  - WorkflowsSupervisor(DynamicSupervisor)
    - WorkflowSupervisor(Supervisor)
      - TaskSupervisor(DynamicSupervisor)
        - Task(:gen_statem)
      - CaseSupervisor(DynamicSupervisor)
        - Case(:gen_statem)
      - WorkitemSupervisor(DynamicSupervisor)
        - Workitem(:gen_statem)
