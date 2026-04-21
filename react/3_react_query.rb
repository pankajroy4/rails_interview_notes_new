Question 1: What is React Query?

Answer -> React Query( now known as TanStack Query ) is a data-fetching and state management library for server data.
          It handles:
            caching
            background refetching
            loading/error states
            synchronization with server

In modern apps we use useQuery hook (provided by React Query library) for fetching the data.
We use useMutation hook for action like update, delete, login etc.

  Example 1:
    import { useQuery } from "@tanstack/react-query";

    const fetchUsers = async () => {
      const res = await fetch("/api/users");
      return res.json();
    };

    const Users = () => {
      const { data, isLoading, error } = useQuery({
        queryKey: ["users"],
        queryFn: fetchUsers,
      });

      if (isLoading) return <p>Loading...</p>;
      if (error) return <p>Error...</p>;

      return (
        <div>
          {data.map(user => (
            <p key={user.id}>{user.name}</p>
          ))}
        </div>
      );
    };

    export default Users;

  Example 2:
    import { useMutation } from "@tanstack/react-query";

    const deleteUser = async (id) => {
      await fetch(`/api/users/${id}`, {
        method: "DELETE",
      });
    };
 
    const DeleteButton = ({ id }) => {
      const mutation = useMutation({
        mutationFn: deleteUser,
      });

      return (
        <button onClick={() => mutation.mutate(id)}>
          Delete
        </button>
      );
    };

    export default DeleteButton;


NOTE: Manual version (without React Query):
    If we do not use React Query then we have to handle everything . Somethig like this:

    Example 1: 
        import { useEffect, useState } from "react";

        const Users = () => {
          const [data, setData] = useState([]);
          const [isLoading, setIsLoading] = useState(true);
          const [error, setError] = useState(null);

          useEffect(() => {
            const fetchUsers = async () => {
              try {
                setIsLoading(true);

                const res = await fetch("/api/users");

                if (!res.ok) {
                  throw new Error("Failed to fetch users");
                }

                const result = await res.json();
                setData(result);
              } catch (err) {
                setError(err.message);
              } finally {
                setIsLoading(false);
              }
            };

            fetchUsers();
          }, []);

          if (isLoading) return <p>Loading...</p>;
          if (error) return <p>Error: {error}</p>;

          return (
            <div>
              {data.map(user => (
                <p key={user.id}>{user.name}</p>
              ))}
            </div>
          );
        };

        export default Users;    



    Example 2:
        import { useState } from "react";

        const DeleteButton = ({ id, onSuccess }) => {
          const [isLoading, setIsLoading] = useState(false);
          const [error, setError] = useState(null);

          const handleDelete = async () => {
            try {
              setIsLoading(true);
              setError(null);

              const res = await fetch(`/api/users/${id}`, {
                method: "DELETE",
              });

              if (!res.ok) {
                throw new Error("Failed to delete user");
              }

              // notify parent to update UI
              if (onSuccess) {
                onSuccess(id);
              }

            } catch (err) {
              setError(err.message);
            } finally {
              setIsLoading(false);
            }
          };

          return (
            <>
              <button onClick={handleDelete} disabled={isLoading}>
                {isLoading ? "Deleting..." : "Delete"}
              </button>

              {error && <p style={{ color: "red" }}>{error}</p>}
            </>
          );
        };

        export default DeleteButton;

      Also we have update UI in parent component:
        import { useState } from "react";
        import DeleteButton from "./DeleteButton";

        const Users = () => {
          const [users, setUsers] = useState([
            { id: 1, name: "A" },
            { id: 2, name: "B" },
          ]);

          const handleDeleteSuccess = (id) => {
            setUsers(prev => prev.filter(user => user.id !== id));
          };

          return (
            <div>
              {users.map(user => (
                <div key={user.id}>
                  <span>{user.name}</span>
                  <DeleteButton id={user.id} onSuccess={handleDeleteSuccess} />
                </div>
              ))}
            </div>
          );
        };

        export default Users;

--------------------------------------------------------------------------------------------------------
Question 2: 