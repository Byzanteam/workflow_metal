defmodule WorkflowMetal.Utils.ETS do
  @moduledoc """
  Some ETS helpers.
  """

  @type condition :: tuple()

  @doc """
  Make the condition.

  ## Example:
  ### `:in`

      iex> WorkflowMetal.Utils.ETS.make_condition(nil, :"$1", :in)
      nil

      iex> WorkflowMetal.Utils.ETS.make_condition([], :"$1", :in)
      nil

      iex> WorkflowMetal.Utils.ETS.make_condition([1], :"$1", :in)
      {:"=:=", :"$1", 1}

      iex> WorkflowMetal.Utils.ETS.make_condition([1, 2], :"$1", :in)
      {:andalso, {:"=:=", :"$1", 1}, {:"=:=", :"$1", 2}}

      iex> WorkflowMetal.Utils.ETS.make_condition([1, 2, 3], :"$1", :in)
      {:andalso, {:andalso, {:"=:=", :"$1", 1}, {:"=:=", :"$1", 2}}, {:"=:=", :"$1", 3}}

  ### `:"=:="`

      iex> WorkflowMetal.Utils.ETS.make_condition(1, :"$1", :"=:=")
      {:"=:=", :"$1", 1}
  """
  @spec make_condition(any, atom(), atom()) :: condition
  def make_condition(nil, _variable, :in), do: nil
  def make_condition([], _variable, :in), do: nil
  def make_condition([item], variable, :in), do: make_condition(item, variable, :"=:=")

  def make_condition(list, variable, :in) when is_list(list) do
    list
    |> Enum.map(&make_condition(&1, variable, :"=:="))
    |> make_and()
  end

  def make_condition(item, variable, :"=:="), do: {:"=:=", variable, item}

  @doc """
  Make an `:or` condition from conditions.

  ## Example:

      iex> WorkflowMetal.Utils.ETS.make_or([])
      nil

      iex> WorkflowMetal.Utils.ETS.make_or([{:"=:=", :"$1", 1}])
      {:"=:=", :"$1", 1}

      iex> WorkflowMetal.Utils.ETS.make_or([{:"=:=", :"$1", 1}, {:"=:=", :"$1", 2}])
      {:orelse, {:"=:=", :"$1", 1}, {:"=:=", :"$1", 2}}
  """
  @spec make_or([condition]) :: condition
  def make_or(conditions) when is_list(conditions), do: merge_conditions(:orelse, conditions)

  @doc """
  Make an `:and` condition from conditions.

  ## Example:

      iex> WorkflowMetal.Utils.ETS.make_and([])
      nil

      iex> WorkflowMetal.Utils.ETS.make_and([{:"=:=", :"$1", 1}])
      {:"=:=", :"$1", 1}

      iex> WorkflowMetal.Utils.ETS.make_and([{:"=:=", :"$1", 1}, {:"=:=", :"$1", 2}])
      {:andalso, {:"=:=", :"$1", 1}, {:"=:=", :"$1", 2}}
  """
  @spec make_and([condition]) :: condition
  def make_and(conditions) when is_list(conditions), do: merge_conditions(:andalso, conditions)

  # merge conditions in `:or` or `:and`
  defp merge_conditions(_operator, nil, nil), do: nil
  defp merge_conditions(_operator, condition, nil), do: condition
  defp merge_conditions(_operator, nil, condition), do: condition
  defp merge_conditions(operator, left, right), do: {operator, left, right}

  defp merge_conditions(operator, []), do: merge_conditions(operator, nil, nil)
  defp merge_conditions(operator, [condition]), do: merge_conditions(operator, condition, nil)

  defp merge_conditions(operator, [left, right | rest]) do
    merge_conditions(
      operator,
      [
        merge_conditions(operator, left, right)
        | rest
      ]
    )
  end
end
